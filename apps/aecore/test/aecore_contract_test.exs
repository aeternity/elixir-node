defmodule AecoreContractTest do
  @moduledoc """
  Unit tests for the Aecore.Contract modules

  This file will be changed when we add contract transactions
  """

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Contract.Call, as: Call
  alias Aecore.Contract.CallStateTree, as: CallStateTree
  alias Aecore.Contract.Contract
  alias Aecore.Contract.ContractStateTree
  alias Aecore.Keys.Wallet
  alias Aecore.Account.Account

  setup do
    Code.require_file("test_utils.ex", "./test")

    Persistence.start_link([])
    Miner.start_link([])
    Chain.clear_state()
    Pool.get_and_empty_pool()

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)
  end

  test "test create and get call" do
    tree = CallStateTree.init_empty()

    caller_address = %Aecore.Chain.Identifier{
      type: :contract,
      value: <<1>>
    }

    contract_address = %Aecore.Chain.Identifier{
      type: :contract,
      value: <<2>>
    }

    caller_nonce = 1
    height = 1
    gas_price = 1

    call =
      Call.new(
        caller_address,
        caller_nonce,
        height,
        contract_address,
        gas_price
      )

    call_id = Call.id(call)
    updated_tree = CallStateTree.insert_call(tree, call)

    key = CallStateTree.construct_call_tree_id(contract_address, call_id)

    get_call = CallStateTree.get_call(updated_tree, key)

    assert call == get_call
  end

  test "create, get and update contract" do
    tree = ContractStateTree.init_empty()
    contract = create_contract()

    tree = ContractStateTree.insert_contract(tree, contract)
    saved_contract = ContractStateTree.get_contract(tree, contract.id.value)
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

    tree = ContractStateTree.enter_contract(tree, updated_storage_contract)
    updated_contract = ContractStateTree.get_contract(tree, updated_storage_contract.id.value)
    assert updated_storage_contract.store === updated_contract.store
  end

  defp create_contract() do
    pubkey = Wallet.get_public_key()

    Contract.new(
      pubkey,
      Account.nonce(TestUtils.get_accounts_chainstate(), pubkey) + 1,
      1,
      <<"THIS IS NOT ACTUALLY PROPER BYTE CODE">>,
      100
    )
  end
end
