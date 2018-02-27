defmodule Aecore.SigningPrototype.Contract do

  alias Aecore.Structures.ContractProposalTx
  alias Aecore.Structures.ContractSignTx
  alias Aecore.Structures.SignedTx
  alias Aecore.SigningPrototype.Validation, as: SigningValidation
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Txs.Pool.Worker, as: Pool

  def add_proposal(name, contract_hash, participants, from_acc, ttl, fee, nonce) do
    {:ok, data} =
      ContractProposalTx.create(name, contract_hash, participants, from_acc, ttl, fee, nonce)
    Pool.add_transaction(sign_tx(data))
  end

  def add_signing(signature, from_acc, contract_hash, fee, nonce) do
    {:ok, data} =
      ContractSignTx.create(signature, from_acc, contract_hash, fee, nonce)
    case SigningValidation.validate(data) do
      true -> Pool.add_transaction(sign_tx(data))
      false -> :error
    end
  end

  defp sign_tx(data) do
    {:ok, signature} = Keys.sign(data)
    %SignedTx{signature: signature, data: data}
  end

end
