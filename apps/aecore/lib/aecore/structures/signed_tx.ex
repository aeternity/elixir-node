defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aeutil.Serialization

  @type t :: %SignedTx{
    data: SpendTx.t() | DataTx.t(),
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
    case tx.data do
      %DataTx{} ->
        tx.data.fee >= 0 && Keys.verify_tx(tx)
      %SpendTx{} ->
        tx.data.value >= 0 && tx.data.fee >= 0 && Keys.verify_tx(tx)
    end
  end

  @spec is_spend_tx(map()) :: boolean()
  def is_spend_tx(tx) do
    Map.has_key?(tx, "from_acc") && Map.has_key?(tx, "to_acc") &&
    Map.has_key?(tx, "value") && Map.has_key?(tx, "nonce") &&
    Map.has_key?(tx, "fee") && Map.has_key?(tx, "lock_time_block")
  end

  @spec is_data_tx(map()) :: boolean()
  def is_data_tx(tx) do
    Map.has_key?(tx, "type") && Map.has_key?(tx, "payload") &&
    Map.has_key?(tx, "from_acc") && Map.has_key?(tx, "fee") &&
    Map.has_key?(tx, "nonce")
  end

  @spec hash_tx(SignedTx.t()) :: binary()
  def hash_tx(%SignedTx{data: data}) do
    :crypto.hash(:sha256, Serialization.pack_binary(data))
  end
end
