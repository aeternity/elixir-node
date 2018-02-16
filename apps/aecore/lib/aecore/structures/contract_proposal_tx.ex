defmodule Aecore.Structures.ContractProposalTx do

  alias __MODULE__

  @type t :: %ContractProposalTx {
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

  @spec create(binary(), string(), integer(), integer()) :: t
  def create(creator, contract, fee, nonce) do
    {:ok, %ContractProposalTx{
        creator: creator,
        contract: contract,
        fee: fee,
        nonce: nonce
      }}
  end

end
