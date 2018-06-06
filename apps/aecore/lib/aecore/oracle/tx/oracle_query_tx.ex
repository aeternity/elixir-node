defmodule Aecore.Oracle.Tx.OracleQueryTx do
  @moduledoc """
  Contains the transaction structure for oracle queries
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Oracle.Oracle
  alias Aeutil.Bits
  alias Aeutil.Hash
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate

  @type id :: binary()

  @type payload :: %{
          oracle_address: Wallet.pubkey(),
          query_data: Oracle.json(),
          query_fee: non_neg_integer(),
          query_ttl: Oracle.ttl(),
          response_ttl: Oracle.ttl()
        }

  @type t :: %OracleQueryTx{
          oracle_address: Wallet.pubkey(),
          query_data: Oracle.json(),
          query_fee: non_neg_integer(),
          query_ttl: Oracle.ttl(),
          response_ttl: Oracle.ttl()
        }

  @type tx_type_state() :: Chainstate.oracles()

  @nonce_size 256

  defstruct [
    :oracle_address,
    :query_data,
    :query_fee,
    :query_ttl,
    :response_ttl
  ]

  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  @spec init(payload()) :: t()
  def init(%{
        oracle_address: oracle_address,
        query_data: query_data,
        query_fee: query_fee,
        query_ttl: query_ttl,
        response_ttl: response_ttl
      }) do
    %OracleQueryTx{
      oracle_address: oracle_address,
      query_data: query_data,
      query_fee: query_fee,
      query_ttl: query_ttl,
      response_ttl: response_ttl
    }
  end

  @spec validate(t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(
        %OracleQueryTx{
          query_ttl: query_ttl,
          response_ttl: response_ttl,
          oracle_address: oracle_address
        },
        data_tx
      ) do
    senders = DataTx.senders(data_tx)

    cond do
      !Oracle.ttl_is_valid?(query_ttl) ->
        {:error, "#{__MODULE__}: Invalid query ttl"}

      !Oracle.ttl_is_valid?(response_ttl) ->
        {:error, "#{__MODULE__}: Invalid response ttl"}

      !match?(%{type: :relative}, response_ttl) ->
        {:error, "#{__MODULE__}: Invalid ttl type"}

      !Wallet.key_size_valid?(oracle_address) ->
        {:error, "#{__MODULE__}: oracle_adddress size invalid"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec process_chainstate(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), tx_type_state()}}
  def process_chainstate(
        accounts,
        %{interaction_objects: interaction_objects} = oracle_state,
        block_height,
        %OracleQueryTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    nonce = DataTx.nonce(data_tx)

    updated_accounts_state =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, tx.query_fee * -1)
      end)

    interaction_object_id = OracleQueryTx.id(sender, nonce, tx.oracle_address)

    updated_interaction_objects =
      Map.put(interaction_objects, interaction_object_id, %{
        sender_address: sender,
        sender_nonce: nonce,
        oracle_address: tx.oracle_address,
        query: tx.query_data,
        has_response: false,
        response: :undefined,
        expires: Oracle.calculate_absolute_ttl(tx.query_ttl, block_height),
        response_ttl: tx.response_ttl.ttl,
        fee: tx.query_fee
      })

    updated_oracle_state = %{
      oracle_state
      | interaction_objects: updated_interaction_objects
    }

    {:ok, {updated_accounts_state, updated_oracle_state}}
  end

  @spec preprocess_check(
          Chainstate.accounts(),
          tx_type_state(),
          non_neg_integer(),
          t(),
          DataTx.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        %{registered_oracles: registered_oracles},
        block_height,
        tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee - tx.query_fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        {:error, "#{__MODULE__}: Invalid transaction TTL: #{inspect(tx.ttl)}"}

      !Map.has_key?(registered_oracles, tx.oracle_address) ->
        {:error, "#{__MODULE__}: No oracle registered with the address:
         #{inspect(tx.oracle_address)}"}

      !Oracle.data_valid?(
        registered_oracles[tx.oracle_address].query_format,
        tx.query_data
      ) ->
        {:error, "#{__MODULE__}: Invalid query data: #{inspect(tx.query_data)}"}

      tx.query_fee < registered_oracles[tx.oracle_address].query_fee ->
        {:error, "#{__MODULE__}: The query fee: #{inspect(tx.query_fee)} is
         lower than the one required by the oracle"}

      !is_minimum_fee_met?(tx, fee, block_height) ->
        {:error, "#{__MODULE__}: Fee: #{inspect(fee)} is too low"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec get_oracle_query_fee(binary()) :: non_neg_integer()
  def get_oracle_query_fee(oracle_address) do
    Chain.registered_oracles()[oracle_address].tx.query_fee
  end

  @spec is_minimum_fee_met?(t(), non_neg_integer(), non_neg_integer() | nil) :: boolean()
  def is_minimum_fee_met?(tx, fee, block_height) do
    tx_query_fee_is_met = tx.query_fee >= Chain.registered_oracles()[tx.oracle_address].query_fee

    tx_fee_is_met =
      case tx.query_ttl do
        %{ttl: ttl, type: :relative} ->
          fee >= calculate_minimum_fee(ttl)

        %{ttl: ttl, type: :absolute} ->
          if block_height != nil do
            fee >=
              ttl
              |> Oracle.calculate_relative_ttl(block_height)
              |> calculate_minimum_fee()
          else
            true
          end
      end

    tx_fee_is_met && tx_query_fee_is_met
  end

  @spec id(Wallet.pubkey(), non_neg_integer(), Wallet.pubkey()) :: binary()
  def id(sender, nonce, oracle_address) do
    bin = sender <> <<nonce::@nonce_size>> <> oracle_address
    Hash.hash(bin)
  end

  def base58c_encode(bin) do
    Bits.encode58c("qy", bin)
  end

  def base58c_decode(<<"qy$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "#{__MODULE__}: Wrong data"}
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]

    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_query_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
