defmodule AecoreNamingTest do
  @moduledoc """
  Unit tests for the Aecore.Naming module
  """

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Structures.Account
  alias Aecore.Naming.Naming
  alias Aecore.Naming.NameUtil

  setup do
    Persistence.start_link([])
    Miner.start_link([])
    Chain.clear_state()
    Pool.get_and_empty_pool()

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)
  end

  test "test naming workflow", setup do
    Miner.mine_sync_block_to_chain()
    {:ok, pre_claim} = Account.pre_claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(pre_claim)
    Miner.mine_sync_block_to_chain()

    naming_state = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state)
    [first_name] = naming_state
    assert first_name.hash == Naming.create_commitment_hash("test.aet", <<1::256>>)
    assert first_name.owner == Wallet.get_public_key()

    {:ok, claim} = Account.claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(claim)
    Miner.mine_sync_block_to_chain()

    naming_state = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state)
    [first_name] = naming_state
    assert first_name.hash == NameUtil.normalized_namehash!("test.aet")
    assert first_name.name == "test.aet"
    assert first_name.owner == Wallet.get_public_key()
    assert first_name.status == :claimed
    assert first_name.pointers == []

    {:ok, update} = Account.name_update("test.aet", "{\"test\": 2}", 5)
    Pool.add_transaction(update)
    Miner.mine_sync_block_to_chain()

    naming_state = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state)
    [first_name] = naming_state
    assert first_name.hash == NameUtil.normalized_namehash!("test.aet")
    assert first_name.name == "test.aet"
    assert first_name.owner == Wallet.get_public_key()
    assert first_name.status == :claimed
    assert first_name.pointers == ["{\"test\": 2}"]

    target_pub_key = Wallet.get_public_key("M/0/1")
    {:ok, transfer} = Account.name_transfer("test.aet", target_pub_key, 5)
    Pool.add_transaction(transfer)
    Miner.mine_sync_block_to_chain()

    naming_state = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state)
    [first_name] = naming_state
    assert first_name.hash == NameUtil.normalized_namehash!("test.aet")
    assert first_name.name == "test.aet"
    assert first_name.owner == Wallet.get_public_key("M/0/1")
    assert first_name.status == :claimed
    assert first_name.pointers == ["{\"test\": 2}"]
  end
end
