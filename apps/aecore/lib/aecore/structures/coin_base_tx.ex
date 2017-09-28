defmodule Aecore.Structures.CoinBaseTx do
  @moduledoc """
  Aecore structure of a coinbase transaction.
  """

  alias Aecore.Structures.CoinBaseTx
  @type coinbase_tx() :: %CoinBaseTx{}

  @doc """
  Definition of Aecore CoinBaseTx structure

  ## Parameters
     - nonce: A random integer generated on initialisation of a transaction.Must be unique
     - from_acc: From account is the public address of one account originating the transaction
     - to_acc: To account is the public address of the account receiving the transaction
     - value: The amount of a transaction
  """
  defstruct nonce: 0,
            from_acc: "",
            to_acc: "",
            value: 10
  use ExConstructor
  alias Aecore.Structures.CoinBaseTx

  @spec create() :: coinbase_tx()
  def create do
    CoinBaseTx.new(%{})
  end
end
