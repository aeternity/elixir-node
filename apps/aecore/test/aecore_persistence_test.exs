defmodule PersistenceTest do
  use ExUnit.Case
  doctest Aecore.Persistence.Worker

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation

  setup persistance_state do
    Persistence.start_link([])
    Miner.start_link([])

    Chain.clear_state()

    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)

    account1 = Wallet.get_public_key()

    account2 =
      <<198, 218, 48, 178, 127, 24, 201, 115, 3, 29, 188, 220, 222, 189, 132, 139, 168, 1, 64,
        134, 103, 38, 151, 213, 195, 5, 219, 138, 29, 137, 119, 229>>

    [account1: account1, account2: account2]
  end

  @tag timeout: 30_000
  @tag :persistence
  test "Get last mined block by his hash from the rocksdb" do
    hash = BlockValidation.block_header_hash(Chain.top_block().header)
    assert {:ok, %{header: _header}} = Persistence.get_block_by_hash(hash)
  end

  @tag timeout: 30_000
  @tag :persistence
  test "Get all blocks from the rocksdb" do
    assert Aecore.Chain.Worker.top_block() ==
             Persistence.get_all_blocks()[Aecore.Chain.Worker.top_block_hash()]
  end

  @tag timeout: 30_000
  @tag :persistence
  test "Get chain state from the rocksdb", persistance_state do
    ## For specific account
    assert {:ok, %{balance: _}} = Persistence.get_account_chain_state(persistance_state.account1)

    ## For all accounts
    all_accounts = Persistence.get_all_accounts_chain_states()
    assert false == Enum.empty?(Map.keys(all_accounts))
  end

  @tag timeout: 20_000
  @tag :persistence
  test "Get latest two blocks from rocksdb", persistance_state do
    top_height = Chain.top_height()

    Map.values(Persistence.get_blocks(2))

    [block1, block2] =
      Enum.sort(Map.values(Persistence.get_blocks(2)), fn b1, b2 ->
        b1.header.height < b2.header.height
      end)

    assert block1.header.height == top_height - 1
    assert block2.header.height == top_height
  end

  @tag timeout: 20_000
  @tag :persistence
  test "Failure cases", persistance_state do
    assert {:error, "bad block structure"} =
             Aecore.Persistence.Worker.add_block_by_hash(:wrong_input_type)

    assert {:error, "bad hash value"} =
             Aecore.Persistence.Worker.get_block_by_hash(:wrong_input_type)

    assert :not_found = Persistence.get_account_chain_state(persistance_state.account2)

    assert "Blocks number must be greater than one" == Persistence.get_blocks(0)
  end
end
