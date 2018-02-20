defmodule Aecore.Structures.ContractProposalTxData do

  alias __MODULE__

  @type t :: %ContractProposalTxData {
    creator: binary(),
    contract: String.t(),
    fee: non_neg_integer(),
    nonce: non_neg_integer()
  }

  defstruct [
    :creator,
    :contract,
    :fee,
    :nonce
  ]

  use ExConstructor

  @spec create(binary(), String.t(), integer(), integer()) :: t
  def create(creator, contract, fee, nonce) do
    {:ok, %ContractProposalTxData{
        creator: creator,
        contract: contract,
        fee: fee,
        nonce: nonce
      }}
  end

end
