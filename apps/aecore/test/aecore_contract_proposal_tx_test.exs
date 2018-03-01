defmodule AecoreContractProposalTxTest do

  use ExUnit.Case
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.SigningPrototype.Contract, as: Contract

  test "add_contract_proposal_tx" do
    {:ok, key} = Keys.pubkey
    assert :ok == Contract.add_proposal("Doc", "testhashtesthash", [key, key], key, 12, 33, 44)
  end

  test "invalid contract_proposal" do
    {:ok, key} = Keys.pubkey
    assert :error == Contract.add_proposal("Doc", "testhashtesthash", [key, key], key, 12, -33, -44)
  end

  test "invalid signing" do
    {:ok, key} = Keys.pubkey
    assert :error == Contract.add_signing("signignaigng", key, "dddffffaaa", 55, 66)
  end
end
