defmodule Aecore.Structures.OracleResponseTxData do
  alias __MODULE__
  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.ChainState
  alias Aecore.Structures.Account

  require Logger

  @type tx_type_state :: ChainState.oracles()

  @type payload :: %{
          query_id: binary(),
          response: map()
        }

  @type t :: %OracleResponseTxData{
          query_id: binary(),
          response: map()
        }

  defstruct [:query_id, :response]
  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name(), do: :oracles

  @spec init(payload()) :: OracleResponseTxData.t()
  def init(%{
        query_id: query_id,
        response: response
      }) do
    %OracleResponseTxData{
      query_id: query_id,
      response: response
    }
  end

  @spec is_valid?(OracleResponseTxData.t()) :: boolean()
  def is_valid?(%OracleResponseTxData{}) do
    true
  end

  @spec process_chainstate!(
          OracleResponseTxData.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(
        %OracleResponseTxData{} = tx,
        from_acc,
        fee,
        nonce,
        block_height,
        accounts,
        %{interaction_objects: interaction_objects} = oracle_state
      ) do
    case preprocess_check(
           tx,
           from_acc,
           Map.get(accounts, from_acc, Account.empty()),
           fee,
           nonce,
           block_height,
           oracle_state
         ) do
      :ok ->
        interaction_object = interaction_objects[tx.query_id]
        query_fee = interaction_object[tx.query_id].query.query_fee

        new_from_account_state =
          Map.get(accounts, from_acc, Account.empty())
          |> deduct_fee(fee - query_fee)

        updated_accounts_chainstate = Map.put(accounts, from_acc, new_from_account_state)

        updated_interaction_objects =
          Map.put(interaction_objects, tx.query_id, %{
            interaction_object
            | response: tx,
              response_height_included: block_height
          })

        updated_oracle_state = %{
          oracle_state
          | interaction_objects: updated_interaction_objects
        }

        {updated_accounts_chainstate, updated_oracle_state}

      {:error, _reason} = err ->
        throw(err)
    end
  end

  @spec preprocess_check(
          OracleResponseTxData.t(),
          Wallet.pubkey(),
          ChainState.account(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, from_acc, account_state, fee, nonce, _block_height, %{
        registered_oracles: registered_oracles,
        interaction_objects: interaction_objects
      }) do
    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      account_state.nonce >= nonce ->
        {:error, "Nonce too small"}

      !Oracle.data_valid?(
        registered_oracles[from_acc].tx.response_format,
        tx.response
      ) ->
        {:error, "Invalid query data"}

      !Map.has_key?(interaction_objects, tx.query_id) ->
        {:error, "No query with that ID"}

      interaction_objects[tx.query_id].response != nil ->
        {:error, "Query already answered"}

      interaction_objects[tx.query_id].query.oracle_address != from_acc ->
        {:error, "Query references a different oracle"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), non_neg_integer()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    referenced_query_response_ttl =
      Chain.oracle_interaction_objects()[tx.data.query_id].query.response_ttl

    tx.data.fee >= calculate_minimum_fee(referenced_query_response_ttl)
  end

  @spec calculate_minimum_fee(integer()) :: integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_response_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
