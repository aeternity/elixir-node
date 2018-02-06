defmodule Aecore.Structures.ContractSignTx do
  require Logger
  alias __MODULE__

  @type t :: %ContractSignTx{
    signature: binary(),
    pub_key: binary(),
    contract_hash: binary(),
    fee: integer()
  }

  defstruct [:signature,
             :pub_key,
             :contract_hash,
             :fee
            ]
  use ExConstructor

  def create(signature, pub_key, contract_hash, fee) do
    {:ok, %ContractSignTx{signature: signature,
                          pub_key: pub_key,
                          contract_hash: contract_hash,
                          fee: fee}}
  end

end
