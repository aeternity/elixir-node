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

  @tag timeout: 100000000
  test "add block" do
    Miner.resume()
    Miner.suspend()

    latest_block = Chain.latest_block()
    latest_block_hash = BlockValidation.block_header_hash(latest_block.header)

    chain_state = Chain.chain_state(latest_block_hash)
    new_block_state = ChainState.calculate_block_state([])
    new_chain_state = ChainState.calculate_chain_state(new_block_state, chain_state)
    new_chain_state_hash = ChainState.calculate_chain_state_hash(new_chain_state)

    block = %Block{header: %Header{height: latest_block.header.height + 1,
                                   prev_hash: latest_block_hash,
                                   txs_hash: <<0::256>>,chain_state_hash: new_chain_state_hash,
                                   difficulty_target: 1, nonce: 0,
                                   timestamp: System.system_time(:milliseconds), version: 1}, txs: []}
    {:ok, nbh} = Aecore.Pow.Cuckoo.generate(block.header)
    block = %{block | header: nbh}

    latest_block = Chain.latest_block()
    latest_block_hash = BlockValidation.block_header_hash(latest_block.header)
    latest_block_hash_hex = latest_block_hash |> Base.encode16()
    [latest_block | [previous_block | []]] = Chain.get_blocks(latest_block_hash, 2)

    assert latest_block == Chain.get_block_by_hex_hash(latest_block_hash_hex)
    assert previous_block.header.height + 1 == latest_block.header.height
    assert BlockValidation.validate_block!(latest_block, previous_block, Chain.chain_state())
    assert :ok = Chain.add_block(block)
    assert latest_block = Chain.latest_block()
    assert latest_block.header.height == block.header.height

    length = length(Chain.all_blocks())
    assert length > 1
  end

end
