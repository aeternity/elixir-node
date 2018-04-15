defmodule Aecore.Tx.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Structures.CoinbaseTx
  alias Aewallet.Signing
  alias Aeutil.Serialization
  alias Aeutil.Bits

  require Logger

  @type t :: %SignedTx{
          data: DataTx.t(),
          signatures: list(Wallet.pubkey())
        }

  @doc """
  Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %SpendTx{} structure
     - signature: Signed %SpendTx{} with the private key of the sender
  """

  defstruct [:data, :signatures]
  use ExConstructor

  @spec create(DataTx.t(), list(Signature.t())) :: SignedTx.t()
  def create(data, signatures \\ []) do
    %SignedTx{data: data, signatures: signatures}
  end

  def data_tx(%SignedTx{data: data}) do data end

  @spec is_coinbase?(SignedTx.t()) :: boolean()
  def is_coinbase?(%SignedTx{data: data}) do
    data.type == CoinbaseTx
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(%SignedTx{data: data} = tx) do
    signatures_valid?(tx) && DataTx.is_valid?(data)
  end

  @spec process_chainstate!(ChainState.chainstate(), non_neg_integer(), SignedTx.t()) :: ChainState.chainstate()
  def process_chainstate!(chainstate, block_height, %SignedTx{data: data}) do
    DataTx.process_chainstate!(chainstate, block_height, data)
  end

  @doc """
  Takes the transaction that needs to be signed
  and the private key of the sender.
  Returns a signed tx

  ## Parameters
     - tx: The transaction data that it's going to be signed
     - priv_key: The priv key to sign with

  """

  @spec sign_tx(DataTx.t() | SignedTx.t(), binary()) :: {:ok, SignedTx.t()}
  def sign_tx(%DataTx{} = tx, priv_key) do
    sign_tx(%SignedTx{data: tx, signatures: []}, priv_key)
  end

  # TODO solve problem of proper ordering of sigs
  def sign_tx(%SignedTx{data: data, signatures: sigs}, priv_key) do
    signature =
      data
      |> Serialization.pack_binary()
      |> Signing.sign(priv_key)
    {:ok, %SignedTx{data: data, signatures: [signature | sigs]}}
  end

  def sign_tx(tx, _priv_key) do
    {:error, "Wrong Transaction data structure: #{inspect(tx)}"}
  end

  @spec hash_tx(SignedTx.t()) :: binary()
  def hash_tx(tx) do
    :crypto.hash(:sha256, Serialization.pack_binary(tx))
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

  @spec serialize(SignedTx.t()) :: map()
  def serialize(%SignedTx{} = tx) do
    signatures_length = length(tx.signatures)
    cond do
      signatures_length == 0 ->
        %{"data" => DataTx.serialize(tx.data)}
      signatures_length == 1 ->
        signature_serialized = 
          tx.signatures
          |> Enum.at(0)
          |> Serialization.serialize_value(:signature)
        %{"data" => DataTx.serialize(tx.data),
          "signature" => signature_serialized}
      true ->
        %{"data" => DataTx.serialize(tx.data),
          "signature" => Serialization.serialize_value(:signature)}
    end
  end

  @spec deserialize(map()) :: DataTx.t()
  def deserialize(tx) do
    signed_tx = Serialization.deserialize_value(tx)
    data = DataTx.deserialize(signed_tx.data)
    cond do
      signed_tx.signature != nil ->
        create(data, [signed_tx.signature])
      signed_tx.signatures != nil ->
        create(data, signed_tx.signatures)
      true ->
        create(data, [])
    end
  end
  
  defp signatures_valid?(%SignedTx{data: data, signatures: sigs}) do
    if length(sigs) != length(DataTx.senders(data)) do
      Logger.error("Wrong signature count")
      false
    else
      data_binary = Serialization.pack_binary(data)

      sigs
      |> Enum.zip(DataTx.senders(data))
      |> Enum.reduce(true, fn {sig, acc}, validity ->
        if Signing.verify(data_binary, sig, acc) do
          validity
        else
          Logger.error("Signature of #{acc} invalid")
          false
        end
      end)
    end
  end
end
