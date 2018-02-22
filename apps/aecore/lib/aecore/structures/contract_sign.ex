defmodule Aecore.Structures.ContractSignTx do
  require Logger
  alias __MODULE__

  @type t :: %ContractSignTx{
    signature: binary(),
    from_acc: binary(),
    contract_hash: binary(),
    fee: integer(),
    nonce: integer()
  }

  defstruct [:signature,
             :from_acc,
             :contract_hash,
             :fee,
             :nonce
            ]
  use ExConstructor

  def create(signature, from_acc, contract_hash, fee, nonce) do
    {:ok, %ContractSignTx{signature: signature,
                          from_acc: from_acc,
                          contract_hash: contract_hash,
                          fee: fee,
                          nonce: nonce}}
  end

end
