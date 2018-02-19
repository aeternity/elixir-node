defmodule Aecore.Structures.SpendTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """
  alias Aeutil.Serialization
  alias Aecore.Structures.SpendTx
  alias Aecore.Keys.Worker, as: Keys

  @type t :: %SpendTx{
    from_acc: binary(),
    to_acc: binary(),
    value: non_neg_integer(),
    nonce: non_neg_integer(),
    fee: non_neg_integer(),
    lock_time_block: non_neg_integer()
  }

  @doc """
  Definition of Aecore SpendTx structure

  ## Parameters
  - nonce: A random integer generated on initialisation of a transaction.Must be unique
  - from_acc: From account is the public address of one account originating the transaction
  - to_acc: To account is the public address of the account receiving the transaction
  - value: The amount of a transaction
  """
  defstruct [:from_acc, :to_acc, :value, :nonce, :fee, :lock_time_block]
  use ExConstructor

  @spec create(binary(), binary(), non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()) :: {:ok, SpendTx.t()}
  def create(from_acc, to_acc, value, nonce, fee, lock_time_block \\ 0) do
    tx_data =
      %SpendTx{from_acc: from_acc,
                to_acc: to_acc,
                value: value,
                nonce: nonce,
                fee: fee,
                lock_time_block: lock_time_block}
    Keys.sign_tx(tx_data)
  end

end
