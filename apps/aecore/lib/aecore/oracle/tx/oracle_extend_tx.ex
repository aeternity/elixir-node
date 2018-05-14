defmodule Aecore.Oracle.Tx.OracleExtendTx do
  @moduledoc """
  Contains the transaction structure for oracle extensions
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__
  alias Aecore.Tx.DataTx
  alias Aecore.Oracle.Oracle
  alias Aecore.Account.AccountStateTree

  require Logger

  @type payload :: %{
          ttl: non_neg_integer()
        }

  @type t :: %OracleExtendTx{
          ttl: non_neg_integer()
        }

  defstruct [:ttl]
  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  @spec init(payload()) :: OracleExtendTx.t()
  def init(%{ttl: ttl}) do
    %OracleExtendTx{ttl: ttl}
  end

  @spec validate(OracleExtendTx.t(), DataTx.t()) :: boolean()
  def validate(%OracleExtendTx{ttl: ttl}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      ttl <= 0 ->
        {:error, "#{__MODULE__}: Negative ttl: #{inspect(ttl)} in OracleExtendTx"}

      length(senders) != 1 ->
        {:error, "#{__MODULE__}: Invalid senders number"}

      true ->
        :ok
    end
  end

  @spec process_chainstate(
          ChainState.account(),
          Oracle.oracles(),
          non_neg_integer(),
          OracleExtendTx.t(),
          DataTx.t()
        ) :: {ChainState.accounts(), Oracle.oracles()}
  def process_chainstate(
        accounts,
        oracle_state,
        _block_height,
        %OracleExtendTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)

    updated_oracle_state =
      update_in(
        oracle_state,
        [:registered_oracles, sender, :expires],
        &(&1 + tx.ttl)
      )

    {:ok, {accounts, updated_oracle_state}}
  end

  @spec preprocess_check(
          ChainState.accounts(),
          Oracle.oracles(),
          non_neg_integer(),
          OracleExtendTx.t(),
          DataTx.t()
        ) :: :ok
  def preprocess_check(
        accounts,
        %{registered_oracles: registered_oracles},
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
        {:error, "#{__MODULE__}: Account - #{inspect(sender)}, isn't a registered operator"}

      fee < calculate_minimum_fee(tx.ttl) ->
        {:error, "#{__MODULE__}: Fee: #{inspect(fee)} is too low"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(
          ChainState.accounts(),
          non_neg_integer(),
          OracleExtendTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: ChainState.account()
  def deduct_fee(accounts, block_height, _tx, data_tx, fee) do
    DataTx.standard_deduct_fee(accounts, block_height, data_tx, fee)
  end

  @spec calculate_minimum_fee(non_neg_integer()) :: non_neg_integer()
  def calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_extend_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
