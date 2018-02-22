defmodule Aecore.Structures.SpendTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aeutil.Serialization

  @typedoc "Arbitrary structure data of a transaction"
  @type payload ::map()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %__MODULE__{
    to_acc: binary(),
    value: non_neg_integer(),
    lock_time_block: non_neg_integer()
  }

  @doc """
  Definition of Aecore SpendTx structure

  ## Parameters
  - to_acc: To account is the public address of the account receiving the transaction
  - value: The amount of a transaction
  - lock_time_block: To which block the funds will become available
  """
  defstruct [:to_acc, :value, :lock_time_block]
  use ExConstructor

  @spec init(payload()) :: SpendTx.t()
  def init(%{to_acc: to_acc, value: value, lock_time_block: lock} = payload) do
    %__MODULE__{to_acc: to_acc,
                value: value,
                lock_time_block: lock}
  end

  @spec is_valid(SpendTx.t()) :: :ok | {:error, reason()}
  def is_valid(%__MODULE__{value: value}) do
    if value >= 0 do
      :ok
    else
      {:error, "Value not enough"}
    end
  end

  @spec reward(SpendTx.t(), account_state(), integer()) :: account_chainstate()
  def reward(%__MODULE__{} = tx, account_state, block_height) do
    transaction_in!(account_state, block_height, tx.value, tx.lock_time_block)
  end

  @spec process_chainstate(%SpendTx.t(), binary(), non_neg_integer(), non_neg_integer(),
                           account_state(), non_neg_integer()) :: account_state()
  def process_chainstate!(%__MODULE__{} = tx, from_acc, fee, nonce, account_state, block_height) do
    case preprocess_check(account_state, fee, tx.value, nonce, block_height) do
      :ok ->
        account_state
        |> deduct_fee(fee, nonce)
        |> transaction_out(block_height, from_acc, tx.value * -1, nonce, -1)
        |> transaction_in(block_height, to_acc, tx.value, lock_time_block)

      {:error, reason} = err ->
        throw err
    end
  end

  def preprocess_check(account_state, fee, value, nonce, block_height) do
    cond do
      account_state.balance - (fee + value) < 0 ->
       {:error, "Negative balance"}

      account_state.nonce >= nonce ->
       {:error, "Nonce too small"}

      block_height <= lock_time_block && account_state.value < 0 ->
       {:error, "Can't lock a negative transaction"}

      true ->
        :ok
    end
  end

  def deduct_fee(account_state, fee, nonce) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  @spec transaction_in(account_state(), integer(), integer(), integer()) :: account_state()
  defp transaction_in(account_state, block_height, value, lock_time_block) do
    if block_height <= lock_time_block do
      new_locked = account_state.locked ++ [%{amount: value, block: lock_time_block}]
      Map.put(account_state, :locked, new_locked)
    else
      new_balance = account_state.balance + value
      Map.put(account_state, :balance, new_balance)
    end
  end

  @spec transaction_out(account_state(), integer(), integer(), integer(), integer()) :: account_state()
  defp transaction_out(account_state, block_height, value, nonce, lock_time_block) do
    account_state
    |> Map.put(:nonce, nonce)
    |> transaction_in(block_height, value, lock_time_block)
  end

end
