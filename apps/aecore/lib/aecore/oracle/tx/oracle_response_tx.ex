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
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate

  @type payload :: %{
          query_id: binary(),
          response: map()
        }

  @type t :: %OracleResponseTx{
          query_id: binary(),
          response: map()
        }

  @type tx_type_state() :: Chainstate.oracles()

  defstruct [:query_id, :response]
  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  @spec init(payload()) :: t()
  def init(%{
        query_id: query_id,
        response: response
      }) do
    %OracleResponseTx{
      query_id: query_id,
      response: response
    }
  end

  @spec validate(t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%OracleResponseTx{query_id: query_id}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      byte_size(query_id) != get_query_id_size() ->
        {:error, "#{__MODULE__}: Wrong query_id size"}

      true ->
        :ok
    end
  end

  @spec get_query_id_size :: non_neg_integer()
  def get_query_id_size do
    Application.get_env(:aecore, :oracle_response_tx)[:query_id]
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
        %OracleResponseTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)

    interaction_object = interaction_objects[tx.query_id]
    query_fee = interaction_object.fee

    updated_accounts_state =
      accounts
      |> AccountStateTree.update(sender, fn acc ->
        Account.apply_transfer!(acc, block_height, query_fee)
      end)

    updated_interaction_objects =
      Map.put(interaction_objects, tx.query_id, %{
        interaction_object
        | response: tx.response,
          expires: interaction_object.expires + interaction_object.response_ttl,
          has_response: true
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
        %{registered_oracles: registered_oracles, interaction_objects: interaction_objects},
        _block_height,
        tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)

    cond do
      AccountStateTree.get(accounts, sender).balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance"}

      !Map.has_key?(registered_oracles, sender) ->
        {:error, "#{__MODULE__}: Sender: #{inspect(sender)} isn't a registered operator"}

      !Oracle.data_valid?(
        registered_oracles[sender].response_format,
        tx.response
      ) ->
        {:error, "#{__MODULE__}: Invalid response data: #{inspect(tx.response)}"}

      !Map.has_key?(interaction_objects, tx.query_id) ->
        {:error, "#{__MODULE__}: No query with the ID: #{inspect(tx.query_id)}"}

      interaction_objects[tx.query_id].response != :undefined ->
        {:error, "#{__MODULE__}: Query already answered"}

      interaction_objects[tx.query_id].oracle_address != sender ->
        {:error, "#{__MODULE__}: Query references a different oracle"}

      !is_minimum_fee_met?(tx, fee) ->
        {:error, "#{__MODULE__}: Fee: #{inspect(fee)} too low"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          Chainstate.accounts(),
          non_neg_integer(),
          OracleResponseTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.accounts()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec is_minimum_fee_met?(t(), non_neg_integer()) :: boolean()
  def is_minimum_fee_met?(tx, fee) do
    referenced_query_response_ttl = Chain.oracle_interaction_objects()[tx.query_id].response_ttl

    fee >= calculate_minimum_fee(referenced_query_response_ttl)
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_response_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
