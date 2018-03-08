defmodule Aecore.Structures.SpendTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aeutil.Serialization
  alias Aeutil.Parser

  @typedoc "Arbitrary structure data of a transaction"
  @type payload :: %__MODULE__{} | map()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Public key of the account"
  @type pub_key() :: binary()

  @typedoc "Structure that holds specific transaction info in the chainstate"
  @type subdomain_chainstate() :: map()

  @typedoc "Structure that holds the account info"
  @type account_state :: %{pub_key() => %{balance: integer(),
                                         locked: [%{amount: integer(), block: integer()}],
                                         nonce: integer()}}

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

  # Callbacks

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
      {:error, "Value cannot be a negative number"}
    end
  end

  @spec reward(SpendTx.t(), integer(), account_state()) :: account_state()
  def reward(%__MODULE__{} = tx, block_height, account_state) do
    transaction_in(account_state, block_height, tx.value, tx.lock_time_block)
  end

  @spec process_chainstate!(SpendTx.t(), binary(), non_neg_integer(), non_neg_integer(),
    non_neg_integer(), account_state(), subdomain_chainstate()) ::
  {account_state(), subdomain_chainstate()}
  def process_chainstate!(%__MODULE__{} = tx, from_acc, fee, nonce, block_height,
                          accounts, %{}) do

    IO.inspect "---------------------------------------"
    h = Aecore.Wallet.Worker.get_public_key("M/0")
    IO.inspect h
    IO.inspect "---------------------------------------"
    case preprocess_check(tx, accounts[from_acc], fee, nonce, block_height, %{}) do
      :ok ->
        new_from_account_state =
          accounts[from_acc]
          |> deduct_fee(fee, nonce)
          |> transaction_out(block_height, tx.value * -1, nonce, -1)
        new_accounts = Map.put(accounts, from_acc, new_from_account_state)

        to_acc = Map.get(accounts, tx.to_acc, %{balance: 0, nonce: 0, locked: []})
        new_to_account_state =
          transaction_in(to_acc, block_height, tx.value, tx.lock_time_block)
        Map.put(new_accounts, tx.to_acc, new_to_account_state)

      {:error, reason} = err ->
        throw err
    end
  end

  def preprocess_check(tx, account_state, fee, nonce, block_height, %{}) do
    cond do
      account_state.balance - (fee + tx.value) < 0 ->
       {:error, "Negative balance"}

      account_state.nonce >= nonce ->
       {:error, "Nonce too small"}

      block_height <= tx.lock_time_block && tx.value < 0 ->
       {:error, "Can't lock a negative transaction"}

      true ->
        :ok
    end
  end

  def deduct_fee(account_state, fee, nonce) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  # Inner functions

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
