defmodule AecoreChainTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

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
    prev_block_hash = BlockValidation.block_header_hash(latest_block.header)
    block = %Block{header: %Header{height: latest_block.header.height + 1, prev_hash: prev_block_hash,
            txs_hash: <<0::256>>,chain_state_hash: <<0::256>>,
            difficulty_target: 0, nonce: 0,
            timestamp: System.system_time(:milliseconds), version: 1}, txs: []}
    assert :ok = Chain.add_block(block)
    assert latest_block = Chain.latest_block()
    assert latest_block.header.height == block.header.height
    length = length(Chain.all_blocks())
    assert length > 1
  end

end
