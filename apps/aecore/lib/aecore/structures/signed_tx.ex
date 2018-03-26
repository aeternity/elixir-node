defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aewallet.Signing
  alias Aeutil.Serialization
  alias Aeutil.Bits

  require Logger

  @type t :: %SignedTx{
          data: DataTx.t(),
          signature: binary()
        }

  @doc """
  Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %SpendTx{} structure
     - signature: Signed %SpendTx{} with the private key of the sender
  """
  defstruct [:data, :signature]
  use ExConstructor

  @spec is_coinbase?(SignedTx.t()) :: boolean()
  def is_coinbase?(%{data: %{sender: key}, signature: signature}) do
    key == nil && signature == nil
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(%SignedTx{data: data} = tx) do
    if Signing.verify(Serialization.pack_binary(data), tx.signature, data.sender) do
      DataTx.is_valid?(data)
    else
      Logger.error("Can't verify the signature with the following public key: #{data.sender}")
      false
    end
  end

  @doc """
  Takes the transaction that needs to be signed
  and the private key of the sender.
  Returns a signed tx

  ## Parameters
     - tx: The transaction data that it's going to be signed
     - priv_key: The priv key to sign with

  """
  @spec sign_tx(DataTx.t(), binary()) :: {:ok, SignedTx.t()}
  def sign_tx(%DataTx{} = tx, priv_key) when byte_size(priv_key) == 32 do
    signature = Signing.sign(Serialization.pack_binary(tx), priv_key)
    {:ok, %SignedTx{data: tx, signature: signature}}
  end

  def sign_tx(%DataTx{} = _tx, priv_key) do
    {:error, "Wrong key size: #{priv_key}"}
  end

  def sign_tx(tx, _priv_key) do
    {:error, "Wrong Transaction data structure: #{inspect(tx)}"}
  end

  @spec hash_tx(SignedTx.t()) :: binary()
  def hash_tx(%SignedTx{data: data}) do
    :crypto.hash(:sha256, Serialization.pack_binary(data))
  end

  @spec reward(DataTx.t(), Account.t()) :: Account.t()
  def reward(%DataTx{type: type, payload: payload}, account_state) do
    type.reward(payload, account_state)
  end

  def base58c_encode(bin) do
    Bits.encode58c("tx", bin)
  end

  def base58c_decode(<<"tx$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "Wrong data"}
  end

  def base58c_encode_root(bin) do
    Bits.encode58c("bx", bin)
  end

  def base58c_decode_root(<<"bx$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode_root(_) do
    {:error, "Wrong data"}
  end
end
