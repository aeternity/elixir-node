defmodule AecoreChainTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Chain.ChainState
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Chain.BlockValidation
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Difficulty

  setup do
    Chain.start_link([])
    []
  end

  @tag timeout: 20_000
  @tag :chain
  test "add block" do
    Miner.mine_sync_block_to_chain

    top_block = Chain.top_block()
    top_block_hash = BlockValidation.block_header_hash(top_block.header)

    chain_state = Chain.chain_state(top_block_hash)
    new_chain_state = ChainState.calculate_and_validate_chain_state!([], chain_state, 1)
    new_chain_state_hash = ChainState.calculate_chain_state_hash(new_chain_state)

    block_unmined = %Block{header: %Header{height: top_block.header.height + 1,
                                   prev_hash: top_block_hash,
                                   txs_hash: <<0::256>>,
                                   chain_state_hash: new_chain_state_hash,
                                   difficulty_target: 1, nonce: 0,
                                   timestamp: System.system_time(:milliseconds),
                                   version: 1}, txs: []}

    {:ok, block_mined} = Miner.mine_sync_block(block_unmined)

    top_block_next = Chain.top_block()
    top_block_hash_next = BlockValidation.block_header_hash(top_block_next.header)
    blocks_for_difficulty_calculation = Chain.get_blocks(top_block_hash_next,
                                              Difficulty.get_number_of_blocks)
    top_block_hash_next_bech32 = top_block_hash_next |> Header.bech32_encode()
    [top_block_from_chain | [previous_block | []]] = Chain.get_blocks(top_block_hash_next, 2)
    previous_block_hash = BlockValidation.block_header_hash(previous_block.header)

    assert top_block_from_chain == Chain.get_block_by_bech32_hash(top_block_hash_next_bech32)
    assert previous_block.header.height + 1 == top_block_from_chain.header.height
    assert BlockValidation.calculate_and_validate_block!(top_block_from_chain, previous_block,
                                                         Chain.chain_state(previous_block_hash),
                                                         blocks_for_difficulty_calculation)
    assert :ok = Chain.add_block(block_mined)
    assert block_mined == Chain.top_block()

    length = length(Chain.longest_blocks_chain())
    assert length > 1
  end

  test "get_block_by_height" do
    Enum.each(0..9, fn (_i) -> Miner.mine_sync_block_to_chain end)
    Enum.each(1..10, fn (i) ->
      assert Chain.get_block_by_height(i).header.height == i
    end)
  end

end
