defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aewallet.Signing

  @typedoc "Structure of the SignedTx module"
  @type t :: %SignedTx{
    data: TxData.t(),
    signature: binary()
  }

  @doc """
  Definition of Aecore SignedTx structure

  ## Parameters
     * data: Aecore %TxData{} structure
     * signature: Signed %TxData{} with the private key of the sender
  """
  defstruct [:data, :signature]
  use ExConstructor

  @spec is_coinbase?(SignedTx.t()) :: boolean()
  def is_coinbase?(%{data: %{from_acc: key}, signature: signature}) do
    key == nil && signature == nil
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(%{data: data, signature: signature}) do
    data.value >= 0 && data.fee >= 0 &&
      Signing.verify(:erlang.term_to_binary(data), signature, data.from_acc)
  end

  @doc """
  Takes the transaction that needs to be signed
  and the private key of the sender.
  Returns a signed tx

  ## Parameters
     - tx: The transaction data that it's going to be signed
     - priv_key: The priv key to sign with

  """
  @spec sign_tx(TxData.t(), binary()) :: {:ok, SignedTx.t()}
  def sign_tx(%TxData{} = tx, priv_key) when byte_size(priv_key) == 32 do
    signature = Signing.sign(:erlang.term_to_binary(tx), priv_key)
    {:ok, %SignedTx{data: tx, signature: signature}}
  end
  def sign_tx(tx, _priv_key) do
    {:error, "Wrong Transaction data structure"}
  end
end
