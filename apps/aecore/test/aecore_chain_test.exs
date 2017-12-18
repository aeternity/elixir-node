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

  @tag timeout: 100_000_000
  test "add block" do
    Miner.resume()
    Miner.suspend()

    top_block = Chain.top_block()
    top_block_hash = BlockValidation.block_header_hash(top_block.header)

    chain_state = Chain.chain_state(top_block_hash)
    new_chain_state = ChainState.calculate_and_validate_chain_state!([], chain_state, 1)
    new_chain_state_hash = ChainState.calculate_chain_state_hash(new_chain_state)

    block = %Block{header: %Header{height: top_block.header.height + 1,
                                   prev_hash: top_block_hash,
                                   txs_hash: <<0::256>>,
                                   chain_state_hash: new_chain_state_hash,
                                   difficulty_target: 1, nonce: 0,
                                   timestamp: System.system_time(:milliseconds),
                                   version: 1}, txs: []}
    {:ok, nbh} = Aecore.Pow.Cuckoo.generate(block.header)
    block = %{block | header: nbh}

    top_block = Chain.top_block()
    top_block_hash = BlockValidation.block_header_hash(top_block.header)
    blocks_for_difficulty_calculation = Chain.get_blocks(top_block_hash,
                                              Difficulty.get_number_of_blocks)
    top_block_hash_hex = top_block_hash |> Base.encode16()
    [top_block | [previous_block | []]] = Chain.get_blocks(top_block_hash, 2)
    previous_block_hash = BlockValidation.block_header_hash(previous_block.header)

    assert top_block == Chain.get_block_by_hex_hash(top_block_hash_hex)
    assert previous_block.header.height + 1 == top_block.header.height
    assert BlockValidation.calculate_and_validate_block!(top_block, previous_block,
                                                         Chain.chain_state(previous_block_hash),
                                                         blocks_for_difficulty_calculation)
    assert :ok = Chain.add_block(block)
    assert top_block = Chain.top_block()
    assert top_block.header.height == block.header.height

    length = length(Chain.longest_blocks_chain())
    assert length > 1
  end

end
