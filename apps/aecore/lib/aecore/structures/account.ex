defmodule Aecore.Structures.Account do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  require Logger
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Account
  alias Aeutil.Bits

  @type locked() :: list(%{amount: non_neg_integer(),
                           block: non_neg_integer()})

  @type t :: %Account{
    balance: non_neg_integer(),
    nonce: non_neg_integer(),
    locked: locked()
  }

  @doc """
  Definition of Account structure

  ## Parameters
  - nonce: Out transaction count
  - balance: The acccount balance
  - locked: A list of maps holding the amount of tokens and block until which they are locked
  """
  defstruct [:balance, :nonce, :locked]
  use ExConstructor

  @spec empty() :: Account.t()
  def empty() do
    %Account{balance: 0,
             nonce: 0,
             locked: []}
  end

  @spec update_locked(Account.t(), integer()) :: Account.t()
  def update_locked(%{locked: locked} = account, new_height) do
    {unlocked_amount, updated_locked} =
      Enum.reduce(locked, {0, []},
        fn(%{amount: amount, block: locked_block} = elem, {updated_amount, updated_locked}) ->
          cond do
            locked_block > new_height ->
              {updated_amount, updated_locked ++ [elem]}

            locked_block == new_height ->
              {updated_amount + amount, updated_locked}

            true ->
              Logger.error(fn -> "Update chain state locked: new block height (#{new_height})
              greater than lock time block (#{locked_block})" end)
              {updated_amount, updated_locked}
          end
        end)
    %Account{account | balance: account.balance + unlocked_amount,
                       locked: updated_locked}
  end

  def base58_encode(bin) do
    Bits.encode58("ak$",bin)
  end
end
