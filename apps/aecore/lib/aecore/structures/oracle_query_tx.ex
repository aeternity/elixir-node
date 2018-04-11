defmodule Aecore.Structures.OracleQueryTx do
  @behaviour Aecore.Structures.Transaction

  alias __MODULE__
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Oracle.Oracle
  alias Aecore.Structures.Chainstate
  alias Aeutil.Bits
  alias Aecore.Structures.AccountStateTree

  require Logger

  @type tx_type_state :: Chainstate.oracles()

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

  @spec is_valid?(OracleQueryTx.t()) :: boolean()
  def is_valid?(%OracleQueryTx{
        query_ttl: query_ttl,
        response_ttl: response_ttl
      }) do
    Oracle.ttl_is_valid?(query_ttl) && Oracle.ttl_is_valid?(response_ttl) &&
      match?(%{type: :relative}, response_ttl)
  end

  @spec process_chainstate!(
          OracleQueryTx.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Chainstate.account(),
          tx_type_state()
        ) :: {Chainstate.accounts(), tx_type_state()}
  def process_chainstate!(
        %OracleQueryTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        %{registered_oracles: registered_oracles, interaction_objects: interaction_objects} =
          oracle_state
      ) do
    preprocess_check!(
      tx,
      sender,
      Account.get_account_state(accounts, sender),
      fee,
      nonce,
      block_height,
      registered_oracles
    )

    new_sender_account_state =
      Account.get_account_state(accounts, sender)
      |> deduct_fee(fee + tx.query_fee)
      |> Map.put(:nonce, nonce)

    updated_accounts_chainstate = AccountStateTree.put(accounts, sender, new_sender_account_state)

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

    {updated_accounts_chainstate, updated_oracle_state}
  end

  @spec preprocess_check!(
          OracleQueryTx.t(),
          Wallet.pubkey(),
          Chainstate.account(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, String.t()}
  def preprocess_check!(tx, _sender, account_state, fee, _nonce, block_height, registered_oracles) do
    cond do
      account_state.balance - fee < 0 ->
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

  @spec deduct_fee(Chainstate.account(), non_neg_integer()) :: Chainstate.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
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
