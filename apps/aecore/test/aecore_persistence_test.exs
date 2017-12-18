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

  @tag timeout: 10_000_000
  @tag :persistence
  test "Reading last mined block by his hash from rocksdb" do
    Miner.resume()
    Miner.suspend()
    hash = BlockValidation.block_header_hash(Chain.top_block().header)
    assert {:ok, %{header: _header}} = Persistence.read_block_by_hash(hash)
  end

  @tag :persistence
  test "Failure cases" do
    assert {:error, "bad block structure"} =
      Aecore.Persistence.Worker.write_block_by_hash(:wrong_input_type)

    assert {:error, "bad hash value"} =
      Aecore.Persistence.Worker.read_block_by_hash(:wrong_input_type)
  end
end
