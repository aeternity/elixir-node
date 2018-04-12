defmodule Aecore.Structures.OracleQueryTx do
  @behaviour Aecore.Structures.Transaction

  alias __MODULE__
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.ChainState
  alias Aeutil.Bits
  alias Aeutil.MapUtil

  require Logger

  @type tx_type_state :: ChainState.oracles()

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
  def get_chain_state_name(), do: :oracles

  @spec init(payload()) :: OracleQueryTx.t()
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
  
  @spec is_valid?(OracleQueryTx.t(), SignedTx.t()) :: boolean()
  def is_valid?(%OracleQueryTx{
        query_ttl: query_ttl,
        response_ttl: response_ttl
      }, signed_tx) do
    senders = signed_tx |> SignedTx.data_tx() |> DataTx.senders()

    cond do
      !Oracle.ttl_is_valid?(query_ttl) ->
        Logger.error("Invalid query ttl")
        false

      !Oracle.ttl_is_valid?(response_ttl) ->
        Logger.error("Invalid response ttl")
        false

      !match?(%{type: :relative}, response_ttl) ->
        Logger.error("Invalid ttl type")
        false

      length(senders) != 1 ->
        Logger.error("Invalid senders number")
        false

      true ->
        true
    end
  end
  
  @spec process_chainstate!(
          ChainState.account(),
          tx_type_state(),
          non_neg_integer(),
          OracleQueryTx.t(),
          SignedTx.t()
  ) :: {ChainState.accounts(), Oracle.oracles()}
  def process_chainstate!(
        accounts,
        %{interaction_objects: interaction_objects} = oracle_state,
        block_height,
        %OracleQueryTx{} = tx,
        signed_tx
  ) do
    sender = signed_tx |> SignedTx.data_tx() |> DataTx.sender()
    nonce = signed_tx |> SignedTx.data_tx() |> DataTx.nonce()

    updated_accounts_state =
      accounts
      |> MapUtil.update(sender, Account.empty(), fn acc ->
        Account.transaction_in!(acc, tx.query_fee * -1)
      end)

    interaction_object_id = OracleQueryTx.id(sender, nonce, tx.oracle_address)

    updated_interaction_objects =
      Map.put(interaction_objects, interaction_object_id, %{
        query: tx,
        query_height_included: block_height,
        query_sender: sender,
        response: nil,
        response_height_included: nil
      })

    updated_oracle_state = %{
      oracle_state
      | interaction_objects: updated_interaction_objects
    }

    {updated_accounts_state, updated_oracle_state}
  end
  
  @spec preprocess_check!(
    ChainState.accounts(),
    Oracle.oracles(),
    non_neg_integer(),
    OracleQueryTx.t(),
    SignedTx.t()
  ) :: :ok
  def preprocess_check!(accounts,
                        %{registered_oracles: registered_oracles},
                        block_height,
                        tx, 
                        signed_tx) do
    data_tx = SignedTx.data_tx(signed_tx)
    sender = DataTx.sender(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      Map.get(accounts, sender, Account.empty()).balance - fee - tx.query_fee < 0 ->
        throw({:error, "Negative balance"})

      !Oracle.tx_ttl_is_valid?(tx, block_height) ->
        throw({:error, "Invalid transaction TTL"})

      !Map.has_key?(registered_oracles, tx.oracle_address) ->
        throw({:error, "No oracle registered with that address"})

      !Oracle.data_valid?(
        registered_oracles[tx.oracle_address].tx.query_format,
        tx.query_data
      ) ->
        throw({:error, "Invalid query data"})

      tx.query_fee < registered_oracles[tx.oracle_address].tx.query_fee ->
        throw({:error, "Query fee lower than the one required by the oracle"})

      !is_minimum_fee_met?(tx, fee, block_height) ->
        throw({:error, "Fee is too low"})

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.accounts(), OracleQueryTx.t(), SignedTx.t(), non_neg_integer()) :: ChainState.account()
  def deduct_fee(accounts, _tx, signed_tx, fee) do
    DataTx.standard_deduct_fee(accounts, signed_tx, fee)
  end

  @spec get_oracle_query_fee(binary()) :: non_neg_integer()
  def get_oracle_query_fee(oracle_address) do
    Chain.registered_oracles()[oracle_address].tx.query_fee
  end

  @spec is_minimum_fee_met?(OracleQueryTx.t(), non_neg_integer(), non_neg_integer() | nil) ::
          boolean()
  def is_minimum_fee_met?(tx, fee, block_height) do
    tx_query_fee_is_met =
      tx.query_fee >= Chain.registered_oracles()[tx.oracle_address].tx.query_fee

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
    :crypto.hash(:sha256, bin)
  end

  def base58c_encode(bin) do
    Bits.encode58c("qy", bin)
  end

  def base58c_decode(<<"qy$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "Wrong data"}
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]

    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_query_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
