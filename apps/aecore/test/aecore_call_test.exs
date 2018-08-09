defmodule AecoreNamingTest do
  @moduledoc """
  Unit tests for the Aecore.Naming module
  """

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Contract.Call, as: Call
  alias Aecore.Contract.CallStateTree, as: CallStateTree

  setup do
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
      Call.new_call(
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
end
