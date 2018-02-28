defmodule Aecore.SigningPrototype.Validation do


  alias Aecore.Structures.ContractProposalTx
  alias Aecore.Structures.ContractSignTx
  alias Aecore.Structures.ContractTx
  alias Aecore.Chain.Worker, as: Chain
  require Logger




  @spec validate(ContractProposalTx.t()) :: boolean()
  def validate(%ContractProposalTx{} = data_proposal) do
    data_proposal.fee >= 0 && data_proposal.nonce >= 0 &&
    is_list(data_proposal.participants) && is_binary(data_proposal.contract_hash) &&
    is_binary(data_proposal.name) && is_integer(data_proposal.fee) &&
    is_integer(data_proposal.nonce)
  end

  @spec validate(ContractSignTx.t()) :: boolean()
  def validate(%ContractSignTx{} = data_sign) do
    case Map.get(Chain.contracts_chainstate(), data_sign.contract_hash) do

      chainstate_data ->
        is_participant?(data_sign,chainstate_data) &&
        is_alive?(data_sign,chainstate_data) &&
        is_signed?(data_sign,chainstate_data)

      nil -> false

    end
  end

  def validate(_data) do
    Logger.error("[Contract Validation] Unknown contract data structure!")
    false
  end

  defp is_participant?(data, chainstate) do
    Enum.find(chainstate.participants, fn x -> x == data.from_acc end) != nil
  end

  defp is_alive?(_data, chainstate) do
    (chainstate.block_height + chainstate.ttl) >= Chain.top_height()
  end
  defp is_signed?(data, chainstate) do
    Enum.find(chainstate.accepted, fn x -> x == data.from_acc end) == nil
  end
end
