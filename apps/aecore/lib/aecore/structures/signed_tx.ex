defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.CoinbaseTx
  alias Aecore.Structures.SignedTx.Signature
  alias Aeutil.Serialization
  alias Aeutil.Bits

  require Logger

  @type t :: %SignedTx{
          data: DataTx.t(),
          signatures: list(Signature.t())
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

  @spec is_coinbase?(SignedTx.t()) :: boolean()
  def is_coinbase?(%SignedTx{data: data}) do
    data.type == CoinbaseTx
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(%SignedTx{data: data} = tx) do
    signatures_valid?(tx) && DataTx.is_valid?(data)
  end

  def process_chainstate!(chainstate, %SignedTx{data: data, signatures: sigs}) do
    sigs
    |> Enum.zip(data.from_accs)
    |> Enum.reduce(chainstate, fn {sig, acc}, chainstate ->
      Signature.process_chainstate!(chainstate, sig, acc, data)
    end)
    |> DataTx.process_chainstate!(data)
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
  def sign_tx(%DataTx{} = tx, nonce, priv_key) do
    sign_tx(%SignedTx{data: tx, signatures: []}, nonce, priv_key)
  end

  # TODO solve problem of proper ordering of sigs
  def sign_tx(%SignedTx{data: data, signatures: sigs}, nonce, priv_key) do
    {:ok, signature} = Signature.sign_tx(data, nonce, priv_key)
    {:ok, %SignedTx{data: data, signatures: [signature | sigs]}}
  end

  def sign_tx(tx, _priv_key) do
    {:error, "Wrong Transaction data structure: #{inspect(tx)}"}
  end

  @spec hash_tx(SignedTx.t()) :: binary()
  def hash_tx(tx) do
    :crypto.hash(:sha256, Serialization.pack_binary(tx))
  end

  @spec reward(DataTx.t(), non_neg_integer(), Account.t()) :: Account.t()
  def reward(%DataTx{type: type, payload: payload}, block_height, account_state) do
    type.reward(payload, block_height, account_state)
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

  @spec get_nonce(SignedTx.t()) :: integer()
  def get_nonce(%SignedTx{signatures: []}) do
    -1
  end

  def get_nonce(%SignedTx{signatures: [sig | _]}) do
    sig.nonce
  end

  defp signatures_valid?(%SignedTx{data: data, signatures: sigs}) do
    if length(sigs) != length(data.from_accs) do
      Logger.error("Not enough signatures")
      false
    else
      sigs
      |> Enum.zip(data.from_accs)
      |> Enum.reduce(true, fn {sig, acc}, validity ->
        if Signature.is_valid?(sig, acc, data) do
          validity
        else
          Logger.error("Signature of #{acc} invalid")
          false
        end
      end)
    end
  end
end
