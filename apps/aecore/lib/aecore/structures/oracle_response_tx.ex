defmodule Aecore.Structures.OracleResponseTx do

  alias __MODULE__
  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.ChainState
  alias Aecore.Structures.Account

  @type payload :: %{
          query_id: binary(),
          response: map()
        }

  @type t :: %OracleResponseTx{
          query_id: binary(),
          response: map()
        }

  defstruct [:query_id, :response]
  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name(), do: :oracles

  @spec init(payload()) :: OracleResponseTx.t()
  def init(%{
        query_id: query_id,
        response: response
      }) do
    %OracleResponseTx{
      query_id: query_id,
      response: response
    }
  end

  @spec is_valid?(OracleResponseTx.t()) :: boolean()
  def is_valid?(%OracleResponseTx{}) do
    :ok
  end

  @spec process_chainstate(
          OracleResponseTx.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          ChainState.account(),
          ChainState.oracles()
        ) :: {ChainState.accounts(), ChainState.oracles()}
  def process_chainstate(
        %OracleResponseTx{} = tx,
        sender,
        fee,
        nonce,
        block_height,
        accounts,
        %{interaction_objects: interaction_objects} = oracle_state
      ) do
    interaction_object = interaction_objects[tx.query_id]
    query_fee = interaction_object.query.query_fee

    new_sender_account_state =
      Map.get(accounts, sender, Account.empty())
      |> Account.transaction_in(query_fee)
      |> deduct_fee(fee)
      |> Map.put(:nonce, nonce)

    updated_accounts_chainstate = Map.put(accounts, sender, new_sender_account_state)

    updated_interaction_objects =
      Map.put(interaction_objects, tx.query_id, %{
        interaction_object
        | response: tx.response,
          response_height_included: block_height
      })

    updated_oracle_state = %{
      oracle_state
      | interaction_objects: updated_interaction_objects
    }

    {updated_accounts_chainstate, updated_oracle_state}
  end

  @spec preprocess_check(
          OracleResponseTx.t(),
          Wallet.pubkey(),
          ChainState.account(),
          non_neg_integer(),
          non_neg_integer(),
          ChainState.oracles()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, sender, account_state, fee, _block_height, %{
        registered_oracles: registered_oracles,
        interaction_objects: interaction_objects
      }) do
    cond do
      account_state.balance - fee < 0 ->
        {:error, "Negative balance"}

      !Map.has_key?(registered_oracles, sender) ->
        {:error, "Sender isn't a registered operator"}

      !Oracle.data_valid?(
        registered_oracles[sender].tx.response_format,
        tx.response
      ) ->
        {:error, "Invalid response data"}

      !Map.has_key?(interaction_objects, tx.query_id) ->
        {:error, "No query with that ID"}

      interaction_objects[tx.query_id].response != nil ->
        {:error, "Query already answered"}

      interaction_objects[tx.query_id].query.oracle_address != sender ->
        {:error, "Query references a different oracle"}

      !is_minimum_fee_met?(tx, fee) ->
        {:error, "Fee too low"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), non_neg_integer()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  @spec is_minimum_fee_met?(OracleResponseTx.t(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(tx, fee) do
    referenced_query_response_ttl =
      Chain.oracle_interaction_objects()[tx.query_id].query.response_ttl.ttl

    fee >= calculate_minimum_fee(referenced_query_response_ttl)
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_response_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
