defmodule PersistenceTest do
  use ExUnit.Case
  doctest Aecore.Persistence.Worker

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Keys
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.Header
  alias Aecore.Account.{Account, AccountStateTree}

  setup do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()
    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  setup do
    account1 = elem(Keys.keypair(:sign), 0)

    account2 =
      <<198, 218, 48, 178, 127, 24, 201, 115, 3, 29, 188, 220, 222, 189, 132, 139, 168, 1, 64,
        134, 103, 38, 151, 213, 195, 5, 219, 138, 29, 137, 119, 229>>

    [account1: account1, account2: account2]
  end

  @tag timeout: 30_000
  @tag :persistence
  test "Get last mined block by his hash from the rocksdb" do
    hash = Header.hash(Chain.top_block().header)
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
    correct_balance =
      Chain.chain_state().accounts
      |> Account.balance(persistance_state.account1)

    # For specific account
    assert match?(%{balance: ^correct_balance}, get_account_state(persistance_state.account1))

    # Non existant accounts are empty
    assert :not_found = get_account_state(persistance_state.account2)

    # For all accounts
    {:ok, all_accounts} = Persistence.get_all_chainstates(Chain.top_block_hash())
    assert false == Enum.empty?(Map.keys(all_accounts))
  end

  @tag timeout: 20_000
  @tag :persistence
  test "Get latest two blocks from rocksdb" do
    top_height = Chain.top_height()

    assert length(Map.values(Persistence.get_all_blocks())) == 4
    assert length(Map.values(Persistence.get_blocks(2))) == 2

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
    root_hashes_map = Persistence.get_all_chainstates(Chain.top_block_hash())
    chainstate = Chain.transform_chainstate(:to_chainstate, root_hashes_map)
    empty_account = Account.empty()

    case AccountStateTree.get(chainstate.accounts, account) do
      ^empty_account -> :not_found
      value -> value
    end
  end
end
