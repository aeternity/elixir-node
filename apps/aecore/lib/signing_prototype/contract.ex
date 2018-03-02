defmodule Aecore.SigningPrototype.Contract do

  alias Aecore.Structures.ContractProposalTx
  alias Aecore.Structures.ContractSignTx
  alias Aecore.Structures.SignedTx
  alias Aecore.SigningPrototype.Validation, as: SigningValidation
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Serialization
  alias Aeutil.Bits

  def add_proposal(name, contract_hash, participants, from_acc, ttl, fee, nonce) do
    {:ok, data} =
      ContractProposalTx.create(name, contract_hash, participants, from_acc, ttl, fee, nonce)
    case SigningValidation.validate(data) do
      true -> Pool.add_transaction(sign_tx(data))
      false -> :error
    end
  end

  def add_signing(signature, from_acc, contract_hash, fee, nonce) do
    {:ok, data} =
      ContractSignTx.create(signature, from_acc, contract_hash, fee, nonce)
    case SigningValidation.validate(data) do
      true -> Pool.add_transaction(sign_tx(data))
      false -> :error
    end
  end

  def form_response(contract_hash) do
    contract =
      Chain.get_contracts_chainstate()
      |> Map.get(contract_hash)
    if contract != nil do
    %{contract_hash: contract_hash,
      participants: Enum.map(contract.participants,
        fn x -> Serialization.hex_binary(x, :serialize) end),
      time_left: time_left(contract),
      is_accepted: is_accepted(contract)}
    end
  end

  def bech32_encode(bin) do
    Bits.bech32_encode("sg", bin)
  end

  defp is_accepted(contract) do
    length(contract.accepted) == length(contract.participants)
  end

  defp time_left(contract) do
    result = contract.ttl +
      contract.block_height - Chain.top_height()
    if result <= 0 do
      "expired"
    else
      result
    end
  end


  defp sign_tx(data) do
    {:ok, signature} = Keys.sign(data)
    %SignedTx{signature: signature, data: data}
  end

end
