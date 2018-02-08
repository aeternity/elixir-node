defmodule Aecore.SigningPrototype.Validation do


  alias Aecore.Structures.ContractProposalTx
  alias Aecore.Structures.ContractSignTx
  alias Aecore.Structures.ContractTx

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
    ## TODO: Write validation on ContractProposalTx
  end

  @spec process(ContractSignTx.t()) :: boolean()
  defp process(%ContractSignTx{} = data_sign) do
    ## TODO: Write validation on ContractSignTx
  end
end
