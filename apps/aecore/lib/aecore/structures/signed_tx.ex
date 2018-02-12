defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.TxData

  @type t :: %SignedTx{
    data: TxData.t(),
    signature: binary()
  }

  @doc """
    Definition of Aecore SignedTx structure

  ## Parameters
     - data: Aecore %TxData{} structure
     - signature: Signed %TxData{} with the private key of the sender
  """
  defstruct [:data, :signature]
  use ExConstructor

  @spec is_coinbase?(SignedTx.t()) :: boolean()
  def is_coinbase?(tx) do
    if(match?(%TxData{}, tx.data)) do
      tx.data.from_acc == nil && tx.signature == nil
    else
      false
    end
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(tx) do
    if(match?(%TxData{}, tx.data)) do
      not_negative = tx.data.value >= 0
      signature_valid = Keys.verify_tx(tx)
      not_negative && signature_valid
    else
      true
    end
  end

  @spec is_oracle_query_tx(map()) :: boolean()
  def is_oracle_query_tx(tx) do
    Map.has_key?(tx, "sender") && Map.has_key?(tx, "oracle_hash") &&
    Map.has_key?(tx, "query_data") && Map.has_key?(tx, "query_fee") &&
    Map.has_key?(tx, "fee") && Map.has_key?(tx, "nonce")
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
    Map.has_key?(tx, "response") && Map.has_key?(tx, "fee") &&
    Map.has_key?(tx, "nonce")
  end
  
  @spec is_tx_data_tx(map()) :: boolean()
  def is_tx_data_tx(tx) do
    Map.has_key?(tx, "from_acc") && Map.has_key?(tx, "to_acc") &&
    Map.has_key?(tx, "value") && Map.has_key?(tx, "nonce") &&
    Map.has_key?(tx, "fee") && Map.has_key?(tx, "lock_time_block")
  end
end
