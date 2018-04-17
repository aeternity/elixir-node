defmodule Aecore.Oracle.Tx.OracleResponseTx do
  @moduledoc """
  Contains the transaction structure for oracle responses
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree

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

  @spec validate(OracleResponseTx.t()) :: :ok
  def validate(%OracleResponseTx{}) do
    :ok
  end

  @spec process_chainstate(
          OracleResponseTx.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          AccountStateTree.tree(),
          Oracle.t()
        ) :: {AccountStateTree.tree(), Oracle.t()}
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
      accounts
      |> Account.get_account_state(sender)
      |> Account.transaction_in(query_fee)
      |> deduct_fee(fee)
      |> Map.put(:nonce, nonce)

    updated_accounts_chainstate = AccountStateTree.put(accounts, sender, new_sender_account_state)

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
          Account.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          Oracle.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, sender, account_state, fee, _nonce, _block_height, %{
        registered_oracles: registered_oracles,
        interaction_objects: interaction_objects
      }) do
    cond do
      account_state.balance - fee < 0 ->
        {:error, "#{__MODULE__}: Negative balance: #{inspect(account_state.balance)}"}

      !Map.has_key?(registered_oracles, sender) ->
        {:error, "#{__MODULE__}: Sender: #{inspect(sender)} isn't a registered operator"}

      !Oracle.data_valid?(
        registered_oracles[sender].tx.response_format,
        tx.response
      ) ->
        {:error, "#{__MODULE__}: Invalid response data: #{inspect(tx.response)}"}

      !Map.has_key?(interaction_objects, tx.query_id) ->
        {:error, "#{__MODULE__}: No query with the ID: #{inspect(tx.query_id)}"}

      interaction_objects[tx.query_id].response != nil ->
        {:error, "#{__MODULE__}: Query already answered"}

      interaction_objects[tx.query_id].query.oracle_address != sender ->
        {:error, "#{__MODULE__}: Query references a different oracle"}

      !is_minimum_fee_met?(tx, fee) ->
        {:error, "#{__MODULE__}: Fee: #{inspect(fee)} too low"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(Account.t(), non_neg_integer()) :: Account.t()
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
