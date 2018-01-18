defmodule PersistenceTest do
  use ExUnit.Case
  doctest Aecore.Persistence.Worker

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation

  setup account do
    Persistence.start_link([])
    Miner.start_link([])
    Miner.mine_sync_block_to_chain
    {:ok, pubkey} = Keys.pubkey()
    [pubkey: pubkey]
  end

  @tag timeout: 10_000
  @tag :persistence
  test "Get last mined block by his hash from the rocksdb" do
    hash = BlockValidation.block_header_hash(Chain.top_block.header)
    assert {:ok, %{header: _header}} = Persistence.get_block_by_hash(hash)
  end

  @tag timeout: 10_000
  @tag :persistence
  test "Get all blocks from the rocksdb" do
    assert Aecore.Chain.Worker.top_block ==
      Persistence.get_all_blocks()[Aecore.Chain.Worker.top_block_hash]
  end

  @tag timeout: 10_000
  @tag :persistence
  test "Get an account from the rocksdb", account do
    assert {:ok, %{balance: _, locked: _}} =
      Persistence.get_account_chain_state(account.pubkey)
  end

  @tag timeout: 10_000
  @tag :persistence
  test "Get all accounts from the rocksdb", account do
    pubkey = account.pubkey
    all_accounts = Persistence.get_all_accounts_chain_states
    assert [^pubkey] = Map.keys(all_accounts)
  end

  @tag :persistence
  test "Failure cases" do
    assert {:error, "bad block structure"} =
      Aecore.Persistence.Worker.add_block_by_hash(:wrong_input_type)

    assert {:error, "bad hash value"} =
      Aecore.Persistence.Worker.get_block_by_hash(:wrong_input_type)
  end
end
