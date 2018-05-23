defmodule PersistenceTest do
  use ExUnit.Case
  doctest Aecore.Persistence.Worker

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account

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
    assert %{balance: _} = get_account_state(persistance_state.account1)

    ## Non existant accounts are empty
    empty = Account.empty()

    assert ^empty =
             AccountStateTree.get(Chain.get_accounts_chainstate(), persistance_state.account2)

    ## For all chainstates
    all_chainstates = Persistence.get_chainstates()
    assert false == Enum.empty?(Map.keys(all_chainstates))
  end

  @tag timeout: 20_000
  @tag :persistence
  test "Get latest two blocks from rocksdb" do
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
    assert {:error, "#{Persistence}: Bad block structure: :wrong_input_type"} ==
             Persistence.add_block_by_hash(:wrong_input_type)

    assert {:error, "#{Persistence}: Bad hash value: :wrong_input_type"} ==
             Persistence.get_block_by_hash(:wrong_input_type)

    assert :not_found = get_account_state(persistance_state.account2)
    assert "Blocks number must be greater than one" == Persistence.get_blocks(0)
  end

  defp get_account_state(account) do
    empty = Account.empty()

    case AccountStateTree.get(Chain.get_accounts_chainstate(), account) do
      ^empty -> :not_found
      value -> value
    end
  end
end
