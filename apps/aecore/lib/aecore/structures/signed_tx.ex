defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SignedTx

  @type t :: %SignedTx{}

  @doc """
    Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %TxData{} structure
     - signature: Signed %TxData{} with the private key of the sender
  """
  defstruct [:data, :signature]
  use ExConstructor

  @spec is_coinbase(SignedTx.t) :: boolean()
  def is_coinbase(tx) do
    tx.data.from_acc == nil && tx.signature == nil
  end

  @spec is_valid(SignedTx.t) :: boolean()
  def is_valid(tx) do
    not_negative = tx.data.value >= 0
    signature_valid = Keys.verify_tx(tx)
    not_negative && signature_valid
  end

end
