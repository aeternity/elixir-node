defmodule AecoreChainTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.Block, as: Block
  alias Aecore.Structures.Header, as:  Header

  setup do
    Chain.start_link()
    []
  end

  test "add block" do
    block = %Block{header: %Header{height: 1, prev_hash: <<1, 24, 45>>, txs_hash: <<12, 123, 12>>, difficulty_target: 0, nonce: 0, timestamp: System.system_time(:milliseconds), version: 1}, txs: []}
    assert :ok = Chain.add_block(block)
    assert latest_block = Chain.latest_block()
    assert latest_block.header.height == block.header.height
  end

  test "latest block" do
    block = %Block{header: %Header{height: 1, prev_hash: <<1, 24, 45>>, txs_hash: <<12, 123, 12>>, difficulty_target: 0, nonce: 0, timestamp: System.system_time(:milliseconds), version: 1}, txs: []}
    assert latest_block = Chain.latest_block()
    assert latest_block.header.height == block.header.height
  end

  test "all blocks" do
    length = length(Chain.all_blocks())
    assert length == 2
  end
  
end
