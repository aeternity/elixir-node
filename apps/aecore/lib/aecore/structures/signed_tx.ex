defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.TxData

  @type signed_tx() :: %SignedTx{}

  @doc """
    Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %TxData{} structure
     - signature: Signed %TxData{} with the private key of the sender
  """
  defstruct [:data, :signature]
  use ExConstructor

  @spec is_coinbase(signed_tx()) :: boolean()
  def is_coinbase(tx) do
    if(match?(%TxData{}, tx.data)) do
      tx.data.from_acc == nil && tx.signature == nil
    else
      false
    end
  end

  @spec is_valid(signed_tx()) :: boolean()
  def is_valid(tx) do
    if(match?(%TxData{}, tx.data)) do
      not_negative = tx.data.value >= 0
      signature_valid = Keys.verify_tx(tx)
      not_negative && signature_valid
    else
      true
    end
  end

end
