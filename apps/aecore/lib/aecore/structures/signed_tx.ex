defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.ContractTx

  @type t :: %SignedTx{
    data: TxData.t() | ContractTx.t() ,
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
    tx.data.from_acc == nil && tx.signature == nil
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(tx) do
    tx.data.value >= 0 && tx.data.fee >= 0 && Keys.verify_tx(tx)
  end

  @spec is_spend_tx(map()) :: boolean()
  def is_spend_tx(tx) do
    Map.has_key?(tx, "from_acc") && Map.has_key?(tx, "to_acc") &&
    Map.has_key?(tx, "value") && Map.has_key?(tx, "nonce") &&
    Map.has_key?(tx, "fee") && Map.has_key?(tx, "lock_time_block")
  end

  def is_contract_proposal_tx(tx) do
    Map.has_key?(tx, "name") && Map.has_key?(tx, "contract_hash") &&
    Map.has_key?(tx, "participants") && Map.has_key?(tx, "from_acc") &&
    Map.has_key?(tx, "ttl") && Map.has_key?(tx, "fee") &&
    Map.has_key?(tx, "nonce")
  end

  def is_contract_sign_tx(tx) do
    Map.has_key?(tx, "signature") && Map.has_key?(tx, "pub_key") &&
    Map.has_key?(tx, "contract_hash") && Map.has_key?(tx, "fee") &&
    Map.has_key?(tx, "nonce")
  end

end
