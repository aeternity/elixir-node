defmodule Aecore.Structures.TxData do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  alias Aecore.Structures.TxData
  @type tx_data() :: %TxData{}

  @doc """
  Definition of Aecore TxData structure

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

  @spec create() :: tx_data()
  def create do
    TxData.new(%{})
  end
end
