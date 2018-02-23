defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.VotingTx
  alias Aeutil.Serialization
  alias Aeutil.Bits

  @type t :: %SignedTx{
    data: SpendTx.t() | VotingTx.t(),

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
  def is_coinbase?(tx) do
    tx.data.from_acc == nil && tx.signature == nil
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(tx) do
    case tx do
      %SignedTx{data: %SpendTx{}} ->
        tx.data.value >= 0 && tx.data.fee >= 0 && Keys.verify_tx(tx)
      %SignedTx{data: %VotingTx{}} ->
        tx.data.data.fee >= 0 && Keys.verify_tx(tx)
    end
  end

  @spec hash_tx(SignedTx.t()) :: binary()
  def hash_tx(%SignedTx{data: data}) do
    :crypto.hash(:sha256, Serialization.pack_binary(data))
  end

  @spec bech32_encode(binary()) :: String.t()
  def bech32_encode(bin) do
    Bits.bech32_encode("tx", bin)
  end

  @spec bech32_encode_root(binary()) :: String.t()
  def bech32_encode_root(bin) do
    Bits.bech32_encode("tr", bin)
  end
end
