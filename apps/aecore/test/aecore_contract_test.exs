defmodule AecoreContractTest do
  @moduledoc """
  Unit tests for the Aecore.Contract modules

  These tests are performed in the scenario of the following simple Solidity contract:

  pragma solidity ^0.4.0;

  contract SimpleStorage {
      uint storedData;

      function set(uint x) public {
          storedData = x;
      }

      function get() public view returns (uint) {
          return storedData;
      }
  }
  """

  use ExUnit.Case

  alias Aecore.Contract.Call
  alias Aecore.Contract.Contract
  alias Aecore.Contract.CallStateTree
  alias Aecore.Contract.ContractStateTree
  alias Aecore.Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aeutil.PatriciaMerkleTree
  alias Aevm.State

  require Aecore.Contract.ContractConstants, as: Constants

  setup do
    Code.require_file("test_utils.ex", "./test")
    Chain.clear_state()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  test "create contract, retrieve and manipulate its storage" do
    Pool.get_and_empty_pool()
    Miner.mine_sync_block_to_chain()

    # create contract
    create_contract()
    Miner.mine_sync_block_to_chain()
    tree_keys1 = PatriciaMerkleTree.all_keys(Chain.chain_state().contracts)
    assert tree_keys1 |> Enum.count() === 1
    contract_address = tree_keys1 |> List.first()
    contract1 = ContractStateTree.get_contract(Chain.chain_state().contracts, contract_address)
    assert contract1.store === %{}
    assert contract1.log === <<>>
    assert contract1.active === true
    assert contract1.referers === []

    # set contract storage
    call_contract(contract_address, "set", 33)
    Miner.mine_sync_block_to_chain()
    tree_keys2 = PatriciaMerkleTree.all_keys(Chain.chain_state().contracts)
    assert tree_keys2 |> Enum.count() === 2
    contract2 = ContractStateTree.get_contract(Chain.chain_state().contracts, contract_address)
    # contract storage is mapping of 32-byte keys to 32-byte values
    assert Map.get(contract2.store, <<0::256>>) === <<33::256>>

    # update contract storage
    call_contract(contract_address, "set", 45)
    Miner.mine_sync_block_to_chain()
    tree_keys3 = PatriciaMerkleTree.all_keys(Chain.chain_state().contracts)
    assert tree_keys3 |> Enum.count() === 2
    contract3 = ContractStateTree.get_contract(Chain.chain_state().contracts, contract_address)
    # contract storage is mapping of 32-byte keys to 32-byte values
    assert Map.get(contract3.store, <<0::256>>) === <<45::256>>

    call_contract(contract_address, "get")
    call_tree_key = compute_call_tree_key(contract_address)
    Miner.mine_sync_block_to_chain()
    call = CallStateTree.get_call(Chain.chain_state().calls, call_tree_key)
    assert call.return_value === <<45::256>>
  end

  defp create_contract do
    Contract.create(
      contract_bytecode_bin(),
      Constants.aevm_solidity_01(),
      1,
      1,
      100_000,
      1,
      <<>>,
      10
    )
  end

  defp call_contract(contract_address, function_name, argument \\ 0) do
    Call.call_contract(
      contract_address,
      Constants.aevm_solidity_01(),
      1,
      100_000,
      1,
      get_function_declaration_signature_hash(function_name) <> <<argument::256>>,
      [],
      10
    )
  end

  defp contract_bytecode_bin do
    State.bytecode_to_bin(
      "608060405234801561001057600080fd5b5060df8061001f6000396000f3006080604052600436106049576000357c0100000000000000000000000000000000000000000000000000000000900463ffffffff16806360fe47b114604e5780636d4ce63c146078575b600080fd5b348015605957600080fd5b5060766004803603810190808035906020019092919050505060a0565b005b348015608357600080fd5b50608a60aa565b6040518082815260200191505060405180910390f35b8060008190555050565b600080549050905600a165627a7a723058200d4dc371ec3b51661664cbded4b6722edf12a97461796fe3ca14264502f265420029"
    )
  end

  defp get_function_declaration_signature_hash(function_name) do
    case function_name do
      "get" ->
        <<109, 76, 230, 60>>

      "set" ->
        <<96, 254, 71, 177>>
    end
  end

  defp compute_call_tree_key(contract_address) do
    {pubkey, _} = Keys.keypair(:sign)
    nonce = Chain.lowest_valid_nonce()
    call_id = Call.id(pubkey, nonce, contract_address)

    CallStateTree.construct_call_tree_id(contract_address, call_id)
  end
end
