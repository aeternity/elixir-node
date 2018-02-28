defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.SpendTx
  alias Aeutil.Serialization
  alias Aeutil.Bits

  @type t :: %SignedTx{
          data: SpendTx.t(),
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
    if match?(%SpendTx{}, tx.data) do
      tx.data.from_acc == nil && tx.signature == nil
    else
      false
    end
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(tx) do
    if match?(%SpendTx{}, tx.data) do
      not_negative = tx.data.value >= 0
      signature_valid = Keys.verify_tx(tx)
      not_negative && signature_valid
    else
      Keys.verify_tx(tx)
    end
  end

  @spec is_oracle_query_tx(map()) :: boolean()
  def is_oracle_query_tx(tx) do
    Map.has_key?(tx, "sender") && Map.has_key?(tx, "oracle_hash") &&
      Map.has_key?(tx, "query_data") && Map.has_key?(tx, "query_fee") && Map.has_key?(tx, "fee") &&
      Map.has_key?(tx, "nonce")
  end

  @spec is_oracle_registration_tx(map()) :: boolean()
  def is_oracle_registration_tx(tx) do
    Map.has_key?(tx, "operator") && Map.has_key?(tx, "query_format") &&
      Map.has_key?(tx, "response_format") && Map.has_key?(tx, "description") &&
      Map.has_key?(tx, "fee") && Map.has_key?(tx, "nonce")
  end

  @spec is_oracle_response_tx(map()) :: boolean()
  def is_oracle_response_tx(tx) do
    Map.has_key?(tx, "operator") && Map.has_key?(tx, "oracle_hash") &&
      Map.has_key?(tx, "response") && Map.has_key?(tx, "fee") && Map.has_key?(tx, "nonce")
  end

  @spec is_spend_tx(map()) :: boolean()
  def is_spend_tx(tx) do
    Map.has_key?(tx, "from_acc") && Map.has_key?(tx, "to_acc") && Map.has_key?(tx, "value") &&
      Map.has_key?(tx, "nonce") && Map.has_key?(tx, "fee") && Map.has_key?(tx, "lock_time_block")
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
