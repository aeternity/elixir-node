defmodule Aecore.Structures.SignedTx do
  @moduledoc """
  Aecore structure of a signed transaction.
  """

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.ContractProposalTxData
  alias Aecore.Structures.ContractCallTxData
  alias Aeutil.Serialization

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
    if(match?(%SpendTx{}, tx.data)) do
      tx.data.from_acc == nil && tx.signature == nil
    else
      false
    end
  end

  @spec is_valid?(SignedTx.t()) :: boolean()
  def is_valid?(tx) do
    case tx.data do
      %SpendTx{} ->
        tx.data.value >= 0 && tx.data.fee >= 0 && Keys.verify_tx(tx)
      %ContractCallTxData{} ->
        if(Map.has_key?(Chain.proposed_contracts(), tx.data.contract_proposal_tx_hash)) do
          true
        else
          false
        end
      _ ->
        true
    end
  end

  @spec hash_tx(SignedTx.t()) :: binary()
  def hash_tx(%SignedTx{data: data}) do
    :crypto.hash(:sha256, Serialization.pack_binary(data))
  end

end
