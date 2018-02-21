defmodule Aecore.Structures.Account do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  require Logger
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Account

  @type t :: %Account{
    balance: non_neg_integer(),
    nonce: non_neg_integer(),
    locked: list(map())
  }

  @doc """
  Definition of Account structure

  ## Parameters
  - nonce: Out transaction count
  - balance: The acccount balance
  - locked: %{amount: non_neq_integer(), block: non_neq_integer()} map with amount of tokens and block when they will go to balance
  """
  defstruct [:balance, :nonce, :locked]
  use ExConstructor

  @spec empty() :: Account.t()
  def empty() do
    %Account{balance: 0,
             nonce: 0,
             locked: []}
  end

  @spec tx_in!(Account.t() | nil, SpendTx.t(), integer()) :: Account.t()
  def tx_in!(nil, tx, block_height) do
    tx_in!(empty(), tx, block_height)
  end
  def tx_in!(account, tx, block_height) do
    if block_height <= tx.lock_time_block do
      if tx.value < 0 do
        throw {:error, "Can't lock a negative transaction"}
      end
      new_locked = account.locked ++ [%{amount: tx.value, block: tx.lock_time_block}]
      %Account{account | locked: new_locked}
    else
      new_balance = account.balance + tx.value
      if new_balance < 0 do
        throw {:error, "Negative balance"}
      end
      %Account{account | balance: new_balance}
    end
  end

  @spec tx_out!(Account.t(), SpendTx.t(), integer()) :: Account.t()
  def tx_out!(account, tx, _block_height) do
    if account.nonce >= tx.nonce do
      throw {:error, "Nonce too small"}
    end
    if tx.value < 0 do
      throw {:error, "Value is negative"}
    end
    new_balance = account.balance - tx.value - tx.fee
    if new_balance < 0 do
      throw {:error, "Negative balance"}
    end
    %Account{account | balance: new_balance, nonce: tx.nonce}
  end

  @spec update_locked(Account.t(), integer()) :: Account.t() 
  def update_locked(account, new_height) do
    {unlocked_amount, updated_locked} = 
      Enum.reduce(
        account.locked,
        {0, []},
        fn(%{amount: amount, block: lock_time_block},
           {amount_update_value, updated_locked}) ->
          cond do
            lock_time_block > new_height ->
              {amount_update_value, 
               updated_locked ++ [%{amount: amount, block: lock_time_block}]}
            lock_time_block == new_height ->
              {amount_update_value + amount, 
               updated_locked}
            true ->
              Logger.error(fn -> "Update chain state locked: new block height (#{new_height}) greater than lock time block (#{lock_time_block})" end)
              {amount_update_value,
               updated_locked}
          end
        end)
    %Account{account | balance: account.balance + unlocked_amount, 
                       locked: updated_locked}
  end

end
