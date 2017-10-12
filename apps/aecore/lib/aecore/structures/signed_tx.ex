defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Structures.TxData

  alias Aecore.Structures.SignedTx
  alias Aecore.Keys.Worker, as: Keys

  @type signed_tx() :: %SignedTx{}

  @doc """
    Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %TxData{} structure
     - signature: Signed %TxData{} with the private key of the sender
  """
  defstruct [:data,
             :signature]
  use ExConstructor



  @doc """
  Takes the public key of the receiver and
  the value that will be sended. Returns signed tx

  ## Parameters
     - to_acc: The public address of the account receiving the transaction
     - value: The amount of a transaction

  """
  @spec create(binary(), integer()) :: %SignedTx{}
  def create(to_acc, value) do
    #TODO remove Keys from here
    {:ok, from_acc} = Keys.pubkey()
    {:ok, tx_data}  = TxData.create(%{:from_acc => from_acc,
      :to_acc   => to_acc,
      :value    => value})
    {:ok, signature} = Keys.sign(tx_data)
    %SignedTx{data: tx_data, signature: signature}
  end

  @doc """
  Takes signed a transaction and then
  verify its signature against the public key

  """
  @spec verify(SignedTx.signed_tx()) :: boolean()
  def verify(%SignedTx{data: data, signature: signature}) do
    Keys.verify(data,signature,data.from_acc)
  end

end
