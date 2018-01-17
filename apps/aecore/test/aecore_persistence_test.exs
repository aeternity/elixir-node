defmodule PersistenceTest do
  use ExUnit.Case
  doctest Aecore.Persistence.Worker

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation

  setup do
    Persistence.start_link([])
    Miner.start_link([])
    []
  end

  @tag timeout: 20_000
  @tag :persistence
  test "Reading last mined block by his hash and the chainstate from rocksdb" do
    {:ok, pubkey} = Aecore.Keys.Worker.pubkey
    Miner.mine_sync_block_to_chain
    hash = BlockValidation.block_header_hash(Chain.top_block.header)
    assert {:ok, %{header: _header}} = Persistence.get_block_by_hash(hash)
    assert {:ok, %{}} = Persistence.get_account_chain_state(pubkey)
  end

  @tag :persistence
  test "Failure cases" do
    assert {:error, "bad block structure"} =
      Aecore.Persistence.Worker.add_block_by_hash(:wrong_input_type)

    assert {:error, "bad hash value"} =
      Aecore.Persistence.Worker.get_block_by_hash(:wrong_input_type)
  end
end
