defmodule Aecore.Oracle.Tx.OracleExtendTx do
  @moduledoc """
  Contains the transaction structure for oracle extensions
  and functions associated with those transactions.
  """

  @behaviour Aecore.Tx.Transaction

  alias __MODULE__

  alias Aecore.Chain.Chainstate
  alias Aecore.Oracle.OracleStateTree
  alias Aecore.Account.AccountStateTree
  alias Aecore.Tx.DataTx

  require Logger

  @type payload :: %{
          ttl: non_neg_integer()
        }

  @type t :: %OracleExtendTx{
          ttl: non_neg_integer()
        }

  @type reason :: String.t()

  defstruct [:ttl]
  use ExConstructor

  @spec get_chain_state_name() :: :oracles
  def get_chain_state_name, do: :oracles

  @spec init(payload()) :: OracleExtendTx.t()
  def init(%{ttl: ttl}) do
    %OracleExtendTx{ttl: ttl}
  end

  @spec validate(OracleExtendTx.t(), DataTx.t()) :: :ok | {:error, reason()}
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
          Chainstate.accounts(),
          Chainstate.oracles(),
          non_neg_integer(),
          OracleExtendTx.t(),
          DataTx.t()
        ) :: {:ok, {Chainstate.accounts(), Chainstate.oracles()}}
  def process_chainstate(
        accounts,
        oracles,
        _block_height,
        %OracleExtendTx{} = tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)

    updated_registered_oracles =
      oracles
      |> OracleStateTree.get_registered_oracles()
      |> update_in([sender, :tx, Access.key(:ttl), :ttl], &(&1 + tx.ttl))

    updated_oracle_state =
      OracleStateTree.put_registered_oracles(oracles, updated_registered_oracles)

    {:ok, {accounts, updated_oracle_state}}
  end

  @spec preprocess_check(
          Chainstate.accounts(),
          Chainstate.oracles(),
          non_neg_integer(),
          OracleExtendTx.t(),
          DataTx.t()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(
        accounts,
        oracles,
        _block_height,
        tx,
        data_tx
      ) do
    sender = DataTx.main_sender(data_tx)
    fee = DataTx.fee(data_tx)
    registered_oracles = OracleStateTree.get_registered_oracles(oracles)

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
          Chainstate.accounts(),
          non_neg_integer(),
          OracleExtendTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: Chainstate.account()
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
