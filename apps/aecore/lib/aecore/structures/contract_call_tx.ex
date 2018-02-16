defmodule Aecore.Structures.ContractCallTx do

  alias __MODULE__
  alias Aecore.Chain.Worker, as: Chain

  require Logger

  @type t :: %ContractCallTx {
    contract_proposal_tx_hash: binary(),
    contract_params: String.t(),
    fee: non_neg_integer(),
    nonce: non_neg_integer()
  }

  defstruct [
    :contract_proposal_tx_hash,
    :contract_params,
    :fee,
    :nonce
  ]

  use ExConstructor

  @spec create(binary(), String.t(), integer(), integer()) :: t
  def create(contract_proposal_tx_hash, contract_params, fee, nonce) do
    proposed_contracts = Chain.proposed_contracts()
    if !Map.has_key(proposed_contracts, contract_proposal_tx_hash) do
      Logger.error("No contract proposed with that hash")
      :error
    else
      {:ok, %ContractCallTx{
          contract_proposal_tx_hash: contract_proposal_tx_hash,
          contract_params: contract_params,
          fee: fee,
          nonce: nonce
        }}
    end
  end

end
