defmodule Aecore.Structures.ContractTx do
  alias __MODULE__
  alias Aecore.Structures.ContractProposalTx
  alias Aecore.Structures.ContractSignTx

  @type t :: %ContractTx{
    data: ContractProposalTx.t() | ContractSignTx.t()
  }

  defstruct [:data]
  use ExConstructor

  end
