defmodule AecoreChainTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Structures.Chainstate
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Chain.BlockValidation
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Difficulty

  setup do
    # Persistence.delete_all_blocks()
    Chain.start_link([])

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)

    []
  end

  @tag timeout: 100_000
  @tag :chain
  test "add block", setup do
    Miner.mine_sync_block_to_chain()

    top_block = Chain.top_block()
    top_block_hash = BlockValidation.block_header_hash(top_block.header)

    chain_state = Chain.chain_state(top_block_hash)

    new_chain_state = Chainstate.calculate_and_validate_chain_state!([], chain_state, 1)

    new_root_hash = Chainstate.calculate_root_hash(new_chain_state)

    block_unmined = %Block{
      header: %Header{
        height: top_block.header.height + 1,
        prev_hash: top_block_hash,
        txs_hash: <<0::256>>,
        root_hash: new_root_hash,
        target: 553_713_663,
        nonce: 0,
        time: System.system_time(:milliseconds),
        version: 1
      },
      txs: []
    }

    {:ok, block_mined} = Miner.mine_sync_block(block_unmined)

    top_block_next = Chain.top_block()

    top_block_hash_next = BlockValidation.block_header_hash(top_block_next.header)

    blocks_for_difficulty_calculation =
      Chain.get_blocks(top_block_hash_next, Difficulty.get_number_of_blocks())

    top_block_hash_next_base58 = top_block_hash_next |> Header.base58c_encode()
    [top_block_from_chain | [previous_block | []]] = Chain.get_blocks(top_block_hash_next, 2)

    previous_block_hash = BlockValidation.block_header_hash(previous_block.header)

    assert top_block_from_chain ==
             top_block_hash_next_base58 |> Chain.get_block_by_base58_hash() |> elem(1)

    assert previous_block.header.height + 1 == top_block_from_chain.header.height

    assert BlockValidation.calculate_and_validate_block!(
             top_block_from_chain,
             previous_block,
             Chain.chain_state(previous_block_hash),
             blocks_for_difficulty_calculation
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
