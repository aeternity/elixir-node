defmodule Aecore.Structures.ContractProposalTx do
  require Logger
  alias __MODULE__

  @type t :: %ContractProposalTx{
    contract_hash: binary(),
    participants: list(),
    ttl: integer(),
    fee: integer()
  }

  defstruct [:name,
             :contract_hash,
             :participants,
             :ttl,
             :fee
            ]
  use ExConstructor

  def create(name, contract_hash, participants, ttl, fee) do
    {:ok, %ContractProposalTx{name: name,
                              contract_hash: contract_hash,
                              participants: participants,
                              ttl: ttl,
                              fee: fee}}
  end

end
