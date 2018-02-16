defmodule Aecore.Structures.ContractProposalTx do
  require Logger
  alias __MODULE__

  @type t :: %ContractProposalTx{
    contract_hash: binary(),
    participants: list(),
    from_acc: binary(),
    ttl: integer(),
    fee: integer(),
    nonce: integer()
  }

  defstruct [:name,
             :contract_hash,
             :participants,
             :from_acc,
             :ttl,
             :fee,
             :nonce
            ]
  use ExConstructor

  def create(name, contract_hash, participants, from_acc, ttl, fee, nonce) do
    {:ok, %ContractProposalTx{name: name,
                              contract_hash: contract_hash,
                              participants: participants,
                              from_acc: from_acc,
                              ttl: ttl,
                              fee: fee,
                              nonce: nonce}}
  end

end
