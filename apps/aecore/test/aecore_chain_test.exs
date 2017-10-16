defmodule AecoreChainTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Chain.ChainState
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner

  setup do
    Chain.start_link()
    []
  end

  test "add block" do
    Miner.resume()
    Miner.suspend()
    latest_block = Chain.latest_block()
    chain_state = Chain.chain_state()
    new_block_state = ChainState.calculate_block_state([])
    new_chain_state = ChainState.calculate_chain_state(new_block_state, chain_state)
    new_chain_state_hash = ChainState.calculate_chain_state_hash(new_chain_state)
    prev_block_hash = BlockValidation.block_header_hash(latest_block.header)
    block = %Block{header: %Header{height: latest_block.header.height + 1,
            prev_hash: prev_block_hash,
            txs_hash: <<0::256>>,chain_state_hash: new_chain_state_hash,
            difficulty_target: 0, nonce: 0,
            timestamp: System.system_time(:milliseconds), version: 1}, txs: []}
    {latest_block, previous_block} = Chain.get_prior_blocks_for_validity_check()
    assert previous_block.header.height + 1 == latest_block.header.height
    assert BlockValidation.validate_block!(latest_block, previous_block,
                                           Chain.chain_state)
    assert :ok = Chain.add_block(block)
    assert latest_block = Chain.latest_block()
    assert latest_block.header.height == block.header.height
    length = length(Chain.all_blocks())
    assert length > 1
  end

end
