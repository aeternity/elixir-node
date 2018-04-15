defmodule Aecore.Oracle.Tx.OracleResponseTx do
  @moduledoc """
  Contains the transaction structure for oracle responses
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction
  
  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree

  require Logger

  @type tx_type_state :: Chainstate.oracles()

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
  def get_chain_state_name, do: :oracles

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

  @spec is_valid?(OracleResponseTx.t(), DataTx.t()) :: boolean()
  def is_valid?(%OracleResponseTx{}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
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
          OracleResponseTx.t(),
          DataTx.t()
  ) :: {ChainState.accounts(), Oracle.oracles()}
  def process_chainstate!(
        accounts,
        %{interaction_objects: interaction_objects} = oracle_state,
        block_height,
        %OracleResponseTx{} = tx,
        data_tx
  ) do
    sender = DataTx.sender(data_tx)

    interaction_object = interaction_objects[tx.query_id]
    query_fee = interaction_object.query.query_fee

    updated_accounts_state =
      accounts
      |> MapUtil.update(sender, Account.empty(), fn acc ->
        Account.transaction_in!(acc, query_fee)
      end)

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

    {updated_accounts_state, updated_oracle_state}
  end
  
  @spec preprocess_check!(
    ChainState.accounts(),
    Oracle.oracles(),
    non_neg_integer(),
    OracleResponseTx.t(),
    DataTx.t()
  ) :: :ok
  def preprocess_check!(accounts,
                        %{registered_oracles: registered_oracles,
                          interaction_objects: interaction_objects},
                        _block_height,
                        tx,
                        data_tx) do
    sender = DataTx.sender(data_tx)
    fee = DataTx.fee(data_tx)
    
    cond do
      Map.get(accounts, sender, Account.empty()).balance - fee < 0 ->
        throw({:error, "Negative balance"})

      !Map.has_key?(registered_oracles, sender) ->
        throw({:error, "Sender isn't a registered operator"})

      !Oracle.data_valid?(
        registered_oracles[sender].tx.response_format,
        tx.response
      ) ->
        throw({:error, "Invalid response data"})

      !Map.has_key?(interaction_objects, tx.query_id) ->
        throw({:error, "No query with that ID"})

      interaction_objects[tx.query_id].response != nil ->
        throw({:error, "Query already answered"})

      interaction_objects[tx.query_id].query.oracle_address != sender ->
        throw({:error, "Query references a different oracle"})

      !is_minimum_fee_met?(tx, fee) ->
        throw({:error, "Fee too low"})

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.accounts(), OracleResponseTx.t(), DataTx.t(), non_neg_integer()) :: ChainState.account()
  def deduct_fee(accounts, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, data_tx, fee)
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
