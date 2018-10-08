defmodule AecoreChainTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Chain.BlockValidation
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Keys
  alias Aecore.Governance.GovernanceConstants

  setup do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  @tag timeout: 100_000
  @tag :chain
  test "add block" do
    Miner.mine_sync_block_to_chain()

    top_block = Chain.top_block()
    top_block_hash = Header.hash(top_block.header)

    {:ok, chain_state} = Chain.chain_state(top_block_hash)

    {:ok, new_chain_state} =
      Chainstate.calculate_and_validate_chain_state(
        [],
        chain_state,
        2,
        elem(Keys.keypair(:sign), 0)
      )

    new_root_hash = Chainstate.calculate_root_hash(new_chain_state)

    block_unmined = %Block{
      header: %Header{
        height: top_block.header.height + 1,
        prev_hash: top_block_hash,
        txs_hash: <<0::256>>,
        root_hash: new_root_hash,
        target: 553_713_663,
        nonce: 0,
        miner: elem(Keys.keypair(:sign), 0),
        time: System.system_time(:milliseconds),
        version: 15
      },
      txs: []
    }

    {:ok, block_mined} = Miner.mine_sync_block(block_unmined)

    top_block_next = Chain.top_block()

    top_block_hash_next = Header.hash(top_block_next.header)

    blocks_for_target_calculation =
      Chain.get_blocks(
        top_block_hash_next,
        GovernanceConstants.number_of_blocks_for_target_recalculation()
      )

    top_block_hash_next_base58 = top_block_hash_next |> Header.base58c_encode()
    [top_block_from_chain | [previous_block | []]] = Chain.get_blocks(top_block_hash_next, 2)

    previous_block_hash = Header.hash(previous_block.header)

    assert {:ok, top_block_from_chain} ==
             Chain.get_block_by_base58_hash(top_block_hash_next_base58)

    assert previous_block.header.height + 1 == top_block_from_chain.header.height

    {:ok, chainstate} = Chain.chain_state(previous_block_hash)

    assert BlockValidation.calculate_and_validate_block(
             top_block_from_chain,
             previous_block,
             chainstate,
             blocks_for_target_calculation
           )

    assert :ok = Chain.add_block(block_mined)
    assert block_mined == Chain.top_block()

    length = length(Chain.longest_blocks_chain())
    assert length > 1
  end

  test "get_block_by_height" do
    Enum.each(0..9, fn _i -> Miner.mine_sync_block_to_chain() end)

    Enum.each(1..10, fn i ->
      assert elem(Chain.get_block_by_height(i), 1).header.height == i
    end)
  end
end
