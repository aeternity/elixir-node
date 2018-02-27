defmodule Aecore.SigningPrototype.Validation do


  alias Aecore.Structures.ContractProposalTx
  alias Aecore.Structures.ContractSignTx
  alias Aecore.Structures.ContractTx
  alias Aecore.Chain.Worker, as: Chain
  require Logger



  @spec validate(ContractTx.t()) :: boolean()
  def validate(%ContractTx{data: data}) do
    process(data)
  end

  def validate(_data) do
    Logger.error("[Contract Validation] Unknown contract data structure!")
    false
  end

  @spec process(ContractProposalTx.t()) :: boolean()
  defp process(%ContractProposalTx{} = data_proposal) do

  end

  @spec process(ContractSignTx.t()) :: boolean()
  defp process(%ContractSignTx{} = data_sign) do
    case Map.get(Chain.contracts_chainstate(), data_sign.contract_hash) do

      chainstate_data ->
        is_participant?(data_sign,chainstate_data) &&
        is_alive?(data_sign,chainstate_data) &&
        is_signed?(data_sign,chainstate_data)

      nil -> false

    end
  end

  defp is_participant?(data, chainstate) do
    Enum.find(chainstate.participants, fn x -> x == data.from_acc end) != nil
  end

  defp is_alive?(_data, chainstate) do
    (chainstate.block_height + chainstate.ttl) <= Chain.top_block_height()
  end
  defp is_signed?(data, chainstate) do
    Enum.find(chainstate.accepted, fn x -> x == data.from_acc end) == nil
  end
end
