defmodule AecoreNamingTest do
  @moduledoc """
  Unit tests for the Aecore.Naming module
  """

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Keys.Wallet
  alias Aecore.Account.Account
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

    naming_state_pre_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_pre_claim)
    [first_name_pre_claim] = naming_state_pre_claim

    assert {:ok, first_name_pre_claim.hash} ==
             Naming.create_commitment_hash("test.aet", <<1::256>>)

    assert first_name_pre_claim.owner == Wallet.get_public_key()

    {:ok, claim} = Account.claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(claim)
    Miner.mine_sync_block_to_chain()

    naming_state_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_claim)
    [first_name_claim] = naming_state_claim
    assert {:ok, first_name_claim.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_claim.name == "test.aet"
    assert first_name_claim.owner == Wallet.get_public_key()
    assert first_name_claim.status == :claimed
    assert first_name_claim.pointers == []

    {:ok, update} = Account.name_update("test.aet", "{\"test\": 2}", 5)
    Pool.add_transaction(update)
    Miner.mine_sync_block_to_chain()

    naming_state_update = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_update)
    [first_name_update] = naming_state_update
    assert {:ok, first_name_update.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_update.name == "test.aet"
    assert first_name_update.owner == Wallet.get_public_key()
    assert first_name_update.status == :claimed
    assert first_name_update.pointers == ["{\"test\": 2}"]

    transfer_to_priv = Wallet.get_private_key("m/0/1")
    transfer_to_pub = Wallet.to_public_key(transfer_to_priv)
    {:ok, transfer} = Account.name_transfer("test.aet", transfer_to_pub, 5)
    Pool.add_transaction(transfer)
    Miner.mine_sync_block_to_chain()

    naming_state_transfer = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_transfer)
    [first_name_transfer] = naming_state_transfer
    assert {:ok, first_name_transfer.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_transfer.name == "test.aet"
    assert first_name_transfer.owner == transfer_to_pub
    assert first_name_transfer.status == :claimed
    assert first_name_transfer.pointers == ["{\"test\": 2}"]

    # fund transfered account
    {:ok, spend} = Account.spend(transfer_to_pub, 5, 5)
    Pool.add_transaction(spend)
    Miner.mine_sync_block_to_chain()

    next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_to_pub) + 1

    {:ok, revoke} =
      Account.name_revoke(transfer_to_pub, transfer_to_priv, "test.aet", 5, next_nonce)

    Pool.add_transaction(revoke)
    Miner.mine_sync_block_to_chain()

    naming_state_revoke = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_revoke)
    [first_name_revoke] = naming_state_revoke
    assert {:ok, first_name_revoke.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_revoke.name == "test.aet"
    assert first_name_revoke.owner == transfer_to_pub
    assert first_name_revoke.status == :revoked
    assert first_name_revoke.pointers == ["{\"test\": 2}"]
  end

  test "not pre-claimed name not claimable", setup do
    {:ok, claim} = Account.claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(claim)
    Miner.mine_sync_block_to_chain()

    naming_state = Map.values(Chain.chain_state().naming)
    assert Enum.empty?(naming_state)
  end

  test "name not claimable with incorrect salt", setup do
    Miner.mine_sync_block_to_chain()
    {:ok, pre_claim} = Account.pre_claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(pre_claim)
    Miner.mine_sync_block_to_chain()

    naming_state_pre_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_pre_claim)
    [first_name_pre_claim] = naming_state_pre_claim

    assert {:ok, first_name_pre_claim.hash} ==
             Naming.create_commitment_hash("test.aet", <<1::256>>)

    assert first_name_pre_claim.owner == Wallet.get_public_key()

    {:ok, claim} = Account.claim("test.aet", <<2::256>>, 5)
    Pool.add_transaction(claim)
    Miner.mine_sync_block_to_chain()

    naming_state_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_claim)
    [first_name_claim] = naming_state_claim
    assert first_name_claim.owner == Wallet.get_public_key()
    assert !Map.has_key?(first_name_claim, :name)
  end

  test "name not claimable from different account", setup do
    Miner.mine_sync_block_to_chain()
    {:ok, pre_claim} = Account.pre_claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(pre_claim)
    Miner.mine_sync_block_to_chain()

    naming_state_pre_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_pre_claim)
    [first_name_pre_claim] = naming_state_pre_claim

    assert {:ok, first_name_pre_claim.hash} ==
             Naming.create_commitment_hash("test.aet", <<1::256>>)

    assert first_name_pre_claim.owner == Wallet.get_public_key()

    claim_priv = Wallet.get_private_key("m/0/1")
    claim_pub = Wallet.to_public_key(claim_priv)

    next_nonce = Account.nonce(Chain.chain_state().accounts, claim_pub) + 1
    {:ok, claim} = Account.claim(claim_pub, claim_priv, "test.aet", <<1::256>>, 5, next_nonce)
    Pool.add_transaction(claim)
    Miner.mine_sync_block_to_chain()

    naming_state_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_claim)
    [first_name_claim] = naming_state_claim
    assert first_name_claim.owner == Wallet.get_public_key()
    assert !Map.has_key?(first_name_claim, :name)
  end

  test "name not updatable from different account", setup do
    Miner.mine_sync_block_to_chain()
    {:ok, pre_claim} = Account.pre_claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(pre_claim)
    Miner.mine_sync_block_to_chain()

    naming_state_pre_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_pre_claim)
    [first_name_pre_claim] = naming_state_pre_claim

    assert {:ok, first_name_pre_claim.hash} ==
             Naming.create_commitment_hash("test.aet", <<1::256>>)

    assert first_name_pre_claim.owner == Wallet.get_public_key()

    {:ok, claim} = Account.claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(claim)
    Miner.mine_sync_block_to_chain()

    naming_state_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_claim)
    [first_name_claim] = naming_state_claim
    assert {:ok, first_name_claim.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_claim.name == "test.aet"
    assert first_name_claim.owner == Wallet.get_public_key()
    assert first_name_claim.status == :claimed
    assert first_name_claim.pointers == []

    update_priv = Wallet.get_private_key("m/0/1")
    update_pub = Wallet.to_public_key(update_priv)
    next_nonce = Account.nonce(Chain.chain_state().accounts, update_pub) + 1

    {:ok, update} =
      Account.name_update(update_pub, update_priv, "test.aet", "{\"test\": 2}", 5, next_nonce)

    Pool.add_transaction(update)
    Miner.mine_sync_block_to_chain()

    naming_state_update = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_update)
    [first_name_update] = naming_state_update
    assert {:ok, first_name_update.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_update.name == "test.aet"
    assert first_name_update.owner == Wallet.get_public_key()
    assert first_name_update.status == :claimed
    assert first_name_update.pointers == []
  end

  test "name not transferable from different account", setup do
    Miner.mine_sync_block_to_chain()
    {:ok, pre_claim} = Account.pre_claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(pre_claim)
    Miner.mine_sync_block_to_chain()

    naming_state_pre_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_pre_claim)
    [first_name_pre_claim] = naming_state_pre_claim

    assert {:ok, first_name_pre_claim.hash} ==
             Naming.create_commitment_hash("test.aet", <<1::256>>)

    assert first_name_pre_claim.owner == Wallet.get_public_key()

    {:ok, claim} = Account.claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(claim)
    Miner.mine_sync_block_to_chain()

    naming_state_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_claim)
    [first_name_claim] = naming_state_claim
    assert {:ok, first_name_claim.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_claim.name == "test.aet"
    assert first_name_claim.owner == Wallet.get_public_key()
    assert first_name_claim.status == :claimed
    assert first_name_claim.pointers == []

    {:ok, update} = Account.name_update("test.aet", "{\"test\": 2}", 5)
    Pool.add_transaction(update)
    Miner.mine_sync_block_to_chain()

    naming_state_update = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_update)
    [first_name_update] = naming_state_update
    assert {:ok, first_name_update.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_update.name == "test.aet"
    assert first_name_update.owner == Wallet.get_public_key()
    assert first_name_update.status == :claimed
    assert first_name_update.pointers == ["{\"test\": 2}"]

    transfer_from_priv = Wallet.get_private_key("m/0/2")
    transfer_from_pub = Wallet.to_public_key(transfer_from_priv)
    next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_from_pub) + 1

    transfer_to_priv = Wallet.get_private_key("m/0/1")
    transfer_to_pub = Wallet.to_public_key(transfer_to_priv)

    {:ok, transfer} =
      Account.name_transfer(
        transfer_from_pub,
        transfer_from_priv,
        "test.aet",
        transfer_to_pub,
        5,
        next_nonce
      )

    Pool.add_transaction(transfer)
    Miner.mine_sync_block_to_chain()

    naming_state_transfer = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_transfer)
    [first_name_transfer] = naming_state_transfer
    assert {:ok, first_name_transfer.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_transfer.name == "test.aet"
    assert first_name_transfer.owner == Wallet.get_public_key()
    assert first_name_transfer.status == :claimed
    assert first_name_transfer.pointers == ["{\"test\": 2}"]
  end

  test "name not revokable from different account", setup do
    Miner.mine_sync_block_to_chain()
    {:ok, pre_claim} = Account.pre_claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(pre_claim)
    Miner.mine_sync_block_to_chain()

    naming_state_pre_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_pre_claim)
    [first_name_pre_claim] = naming_state_pre_claim

    assert {:ok, first_name_pre_claim.hash} ==
             Naming.create_commitment_hash("test.aet", <<1::256>>)

    assert first_name_pre_claim.owner == Wallet.get_public_key()

    {:ok, claim} = Account.claim("test.aet", <<1::256>>, 5)
    Pool.add_transaction(claim)
    Miner.mine_sync_block_to_chain()

    naming_state_claim = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_claim)
    [first_name_claim] = naming_state_claim
    assert {:ok, first_name_claim.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_claim.name == "test.aet"
    assert first_name_claim.owner == Wallet.get_public_key()
    assert first_name_claim.status == :claimed
    assert first_name_claim.pointers == []

    {:ok, update} = Account.name_update("test.aet", "{\"test\": 2}", 5)
    Pool.add_transaction(update)
    Miner.mine_sync_block_to_chain()

    naming_state_update = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_update)
    [first_name_update] = naming_state_update
    assert {:ok, first_name_update.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_update.name == "test.aet"
    assert first_name_update.owner == Wallet.get_public_key()
    assert first_name_update.status == :claimed
    assert first_name_update.pointers == ["{\"test\": 2}"]

    transfer_to_priv = Wallet.get_private_key("m/0/1")
    transfer_to_pub = Wallet.to_public_key(transfer_to_priv)
    {:ok, transfer} = Account.name_transfer("test.aet", transfer_to_pub, 5)
    Pool.add_transaction(transfer)
    Miner.mine_sync_block_to_chain()

    naming_state_transfer = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_transfer)
    [first_name_transfer] = naming_state_transfer
    assert {:ok, first_name_transfer.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_transfer.name == "test.aet"
    assert first_name_transfer.owner == transfer_to_pub
    assert first_name_transfer.status == :claimed
    assert first_name_transfer.pointers == ["{\"test\": 2}"]

    # fund transfered account
    {:ok, spend} = Account.spend(transfer_to_pub, 5, 5)
    Pool.add_transaction(spend)
    Miner.mine_sync_block_to_chain()

    transfer_from_priv = Wallet.get_private_key("m/0/2")
    transfer_from_pub = Wallet.to_public_key(transfer_from_priv)
    next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_from_pub) + 1

    {:ok, revoke} =
      Account.name_revoke(transfer_from_pub, transfer_from_priv, "test.aet", 5, next_nonce)

    Pool.add_transaction(revoke)
    Miner.mine_sync_block_to_chain()

    naming_state_revoke = Map.values(Chain.chain_state().naming)
    assert 1 == Enum.count(naming_state_revoke)
    [first_name_revoke] = naming_state_revoke
    assert {:ok, first_name_revoke.hash} == NameUtil.normalized_namehash("test.aet")
    assert first_name_revoke.name == "test.aet"
    assert first_name_revoke.owner == transfer_to_pub
    assert first_name_revoke.status == :claimed
    assert first_name_revoke.pointers == ["{\"test\": 2}"]
  end
end
