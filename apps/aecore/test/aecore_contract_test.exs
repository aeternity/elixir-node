defmodule AecoreContractTest do
  @moduledoc """
  Unit tests for the Aecore.Contract modules

  This file will be changed when we add contract transactions
  """

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Contract.Call, as: Call
  alias Aecore.Contract.CallStateTree, as: CallStateTree
  alias Aecore.Contract.Contract
  alias Aecore.Contract.ContractStateTree
  alias Aecore.Keys
  alias Aecore.Account.Account

  setup do
    Code.require_file("test_utils.ex", "./test")
    Chain.clear_state()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  test "test create and get call" do
    tree = CallStateTree.init_empty()

    call = create_call()

    call_id = Call.id(call)
    updated_tree = CallStateTree.insert_call(tree, call)

    key = CallStateTree.construct_call_tree_id(call.contract_address, call_id)

    get_call = CallStateTree.get(updated_tree, key)

    assert call == get_call
  end

  test "create, get and update contract" do
    tree = ContractStateTree.init_empty()
    contract = create_contract()

    updated_tree = ContractStateTree.insert_contract(tree, contract)
    saved_contract = ContractStateTree.get(updated_tree, contract.id.value)
    assert contract === saved_contract

    new_contract_storage = %{
      <<"key1">> => <<"value1">>,
      <<"key2">> => <<"value2">>,
      <<"key3">> => <<"value3">>
    }

    updated_storage_contract = %{
      contract
      | store: new_contract_storage
    }

    updated_tree1 = ContractStateTree.enter_contract(tree, updated_storage_contract)

    updated_contract = ContractStateTree.get(updated_tree1, updated_storage_contract.id.value)

    assert updated_storage_contract.store === updated_contract.store
  end

  defp create_call do
    {pubkey, _privkey} = Keys.keypair(:sign)

    Call.new(
      pubkey,
      Account.nonce(TestUtils.get_accounts_chainstate(), pubkey) + 1,
      Chain.top_height(),
      <<"THIS IS NOT AN ACTUALL CONTRACT ADDRESS">>,
      1
    )
  end

  defp create_contract do
    {pubkey, _privkey} = Keys.keypair(:sign)

    Contract.new(
      pubkey,
      Account.nonce(TestUtils.get_accounts_chainstate(), pubkey) + 1,
      1,
      <<"THIS IS NOT ACTUALLY PROPER BYTE CODE">>,
      100
    )
  end
end
