defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx

  @type t :: %SignedTx{
    data: TxData.t(),
    signature: binary()
  }

  @doc """
    Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %TxData{} structure
     - signature: Signed %TxData{} with the private key of the sender
  """
  defstruct [:data, :signature]
  use ExConstructor

  @spec is_coinbase?(SignedTx.t()) :: boolean()
  def is_coinbase?(tx) do
    tx.data.from_acc == nil && tx.signature == nil
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(tx) do
    tx.data.from_acc != nil 
    && tx.data.value >= 0 
    && tx.data.fee >= 0 
    && Keys.verify_tx(tx)
  end

  @spec hash(SignedTx.t()) :: binary()
  def hash(tx) do
    :crypto.hash(:sha256, :erlang.term_to_binary(tx))
  end

end
