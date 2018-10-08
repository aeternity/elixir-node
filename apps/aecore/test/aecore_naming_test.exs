defmodule AecoreNamingTest do
  @moduledoc """
  Unit tests for the Aecore.Naming module
  """

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Keys
  alias Aecore.Account.Account
  alias Aecore.Naming.{NameCommitment, NamingStateTree}
  alias Aecore.Naming.NameUtil
  alias Aeutil.PatriciaMerkleTree

  setup do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  setup do
    %{public: a_pub_key, secret: a_priv_key} = :enacl.sign_keypair()
    %{public: b_pub_key, secret: b_priv_key} = :enacl.sign_keypair()

    [
      a_pub_key: a_pub_key,
      a_priv_key: a_priv_key,
      b_pub_key: b_pub_key,
      b_priv_key: b_priv_key
    ]
  end

  @tag :naming
  test "test naming workflow", setup do
    Miner.mine_sync_block_to_chain()
    pre_claim = Account.pre_claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_1 = Chain.chain_state().naming

    assert 1 == naming_state_1 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    commitment = pre_claim.data.payload.commitment.value
    first_name_pre_claim = NamingStateTree.get(naming_state_1, commitment)

    assert {:ok, first_name_pre_claim.hash.value} ==
             NameCommitment.commitment_hash("test.aet", 123)

    assert first_name_pre_claim.owner == elem(Keys.keypair(:sign), 0)

    Account.claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_2 = Chain.chain_state().naming

    assert 1 == naming_state_2 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    {:ok, claim_hash_1} = NameUtil.normalized_namehash("test.aet")
    first_name_claim = NamingStateTree.get(naming_state_2, claim_hash_1)

    assert {:ok, first_name_claim.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_claim.owner == elem(Keys.keypair(:sign), 0)

    assert first_name_claim.status == :claimed
    assert first_name_claim.pointers == "[]"

    Account.name_update("test.aet", "{\"test\": 2}", 5, 5000, 50)
    Miner.mine_sync_block_to_chain()

    naming_state_3 = Chain.chain_state().naming

    assert 1 == naming_state_3 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    {:ok, claim_hash_2} = NameUtil.normalized_namehash("test.aet")
    first_name_update = NamingStateTree.get(naming_state_3, claim_hash_2)

    assert {:ok, first_name_update.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_update.owner == elem(Keys.keypair(:sign), 0)

    assert first_name_update.status == :claimed
    assert first_name_update.pointers == "{\"test\": 2}"

    transfer_to_priv = setup.a_priv_key
    transfer_to_pub = setup.a_pub_key
    transfer = Account.name_transfer("test.aet", transfer_to_pub, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_4 = Chain.chain_state().naming

    assert 1 == naming_state_4 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    hash_1 = transfer.data.payload.hash.value
    first_name_transfer = NamingStateTree.get(naming_state_4, hash_1)
    assert {:ok, first_name_transfer.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_transfer.owner == transfer_to_pub

    assert first_name_transfer.status == :claimed
    assert first_name_transfer.pointers == "{\"test\": 2}"

    # fund transfered account
    Account.spend(transfer_to_pub, 5, 5, <<"payload">>)
    Miner.mine_sync_block_to_chain()

    next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_to_pub) + 1

    revoke = Account.name_revoke(transfer_to_pub, transfer_to_priv, "test.aet", 5, next_nonce)

    Miner.mine_sync_block_to_chain()

    naming_state_5 = Chain.chain_state().naming

    assert 1 == naming_state_5 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    hash_2 = revoke.data.payload.hash.value
    first_name_revoke = NamingStateTree.get(naming_state_5, hash_2)
    assert {:ok, first_name_revoke.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_revoke.owner == transfer_to_pub

    assert first_name_revoke.status == :revoked
    assert first_name_revoke.pointers == "{\"test\": 2}"
  end

  @tag :naming
  test "not pre-claimed name not claimable" do
    Account.claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state = Chain.chain_state().naming
    {:ok, claim_hash} = NameUtil.normalized_namehash("test.aet")
    claim_2 = NamingStateTree.get(naming_state, claim_hash)
    assert :none == claim_2
  end

  @tag :naming
  test "name not claimable with incorrect salt" do
    Miner.mine_sync_block_to_chain()
    pre_claim = Account.pre_claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_1 = Chain.chain_state().naming

    assert 1 == naming_state_1 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    commitment = pre_claim.data.payload.commitment.value
    first_name_pre_claim = NamingStateTree.get(naming_state_1, commitment)

    assert {:ok, first_name_pre_claim.hash.value} ==
             NameCommitment.commitment_hash("test.aet", 123)

    assert first_name_pre_claim.owner == elem(Keys.keypair(:sign), 0)

    Account.claim("test.aet", 321, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_2 = Chain.chain_state().naming

    assert 1 == naming_state_2 |> PatriciaMerkleTree.all_keys() |> Enum.count()

    assert {:ok, elem(Keys.keypair(:sign), 0)} ==
             naming_state_2
             |> NamingStateTree.get(commitment)
             |> Map.fetch(:owner)

    assert false == naming_state_2 |> NamingStateTree.get(commitment) |> Map.has_key?(:name)
  end

  @tag :naming
  test "name not claimable from different account", setup do
    Miner.mine_sync_block_to_chain()
    pre_claim = Account.pre_claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_1 = Chain.chain_state().naming

    assert 1 == naming_state_1 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    commitment = pre_claim.data.payload.commitment.value
    first_name_pre_claim = NamingStateTree.get(naming_state_1, commitment)

    assert {:ok, first_name_pre_claim.hash.value} ==
             NameCommitment.commitment_hash("test.aet", 123)

    assert first_name_pre_claim.owner == elem(Keys.keypair(:sign), 0)

    claim_priv = setup.a_priv_key
    claim_pub = setup.a_pub_key

    next_nonce = Account.nonce(Chain.chain_state().accounts, claim_pub) + 1
    Account.claim(claim_pub, claim_priv, "test.aet", 123, 5, next_nonce)
    Miner.mine_sync_block_to_chain()

    naming_state_2 = Chain.chain_state().naming

    assert 1 == naming_state_2 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    {:ok, claim_hash} = NameUtil.normalized_namehash("test.aet")
    first_name_claim = NamingStateTree.get(naming_state_2, claim_hash)
    assert :none == first_name_claim

    assert {:ok, elem(Keys.keypair(:sign), 0)} ==
             naming_state_2
             |> NamingStateTree.get(commitment)
             |> Map.fetch(:owner)

    assert false == naming_state_2 |> NamingStateTree.get(commitment) |> Map.has_key?(:name)
  end

  @tag :naming
  test "name not updatable from different account", setup do
    Miner.mine_sync_block_to_chain()
    pre_claim = Account.pre_claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_1 = Chain.chain_state().naming

    assert 1 == naming_state_1 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    commitment = pre_claim.data.payload.commitment.value
    first_name_pre_claim = NamingStateTree.get(naming_state_1, commitment)

    assert {:ok, first_name_pre_claim.hash.value} ==
             NameCommitment.commitment_hash("test.aet", 123)

    assert first_name_pre_claim.owner == elem(Keys.keypair(:sign), 0)

    Account.claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_2 = Chain.chain_state().naming

    assert 1 == naming_state_2 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    {:ok, claim_hash_1} = NameUtil.normalized_namehash("test.aet")
    first_name_claim = NamingStateTree.get(naming_state_2, claim_hash_1)

    assert {:ok, first_name_claim.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_claim.owner == elem(Keys.keypair(:sign), 0)

    assert first_name_claim.status == :claimed
    assert first_name_claim.pointers == "[]"

    update_priv = setup.a_priv_key
    update_pub = setup.a_pub_key
    next_nonce = Account.nonce(Chain.chain_state().accounts, update_pub) + 1

    Account.name_update(
      update_pub,
      update_priv,
      "test.aet",
      "{\"test\": 2}",
      5,
      next_nonce,
      5000,
      50
    )

    Miner.mine_sync_block_to_chain()

    naming_state_3 = Chain.chain_state().naming

    assert 1 == naming_state_3 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    {:ok, claim_hash_2} = NameUtil.normalized_namehash("test.aet")
    first_name_update = NamingStateTree.get(naming_state_3, claim_hash_2)

    assert {:ok, first_name_update.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_update.owner == elem(Keys.keypair(:sign), 0)

    assert first_name_update.status == :claimed
    assert first_name_update.pointers == "[]"
  end

  @tag :naming
  test "name not transferable from different account", setup do
    Miner.mine_sync_block_to_chain()
    pre_claim = Account.pre_claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_1 = Chain.chain_state().naming

    assert 1 == naming_state_1 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    commitment = pre_claim.data.payload.commitment.value
    first_name_pre_claim = NamingStateTree.get(naming_state_1, commitment)

    assert {:ok, first_name_pre_claim.hash.value} ==
             NameCommitment.commitment_hash("test.aet", 123)

    assert first_name_pre_claim.owner == elem(Keys.keypair(:sign), 0)

    Account.claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_2 = Chain.chain_state().naming

    assert 1 == naming_state_2 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    {:ok, claim_hash_1} = NameUtil.normalized_namehash("test.aet")
    first_name_claim = NamingStateTree.get(naming_state_2, claim_hash_1)

    assert {:ok, first_name_claim.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_claim.owner == elem(Keys.keypair(:sign), 0)

    assert first_name_claim.status == :claimed
    assert first_name_claim.pointers == "[]"

    Account.name_update("test.aet", "{\"test\": 2}", 5, 5000, 50)
    Miner.mine_sync_block_to_chain()

    naming_state_3 = Chain.chain_state().naming

    assert 1 == naming_state_3 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    {:ok, claim_hash_2} = NameUtil.normalized_namehash("test.aet")
    first_name_update = NamingStateTree.get(naming_state_3, claim_hash_2)

    assert {:ok, first_name_update.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_update.owner == elem(Keys.keypair(:sign), 0)

    assert first_name_update.status == :claimed
    assert first_name_update.pointers == "{\"test\": 2}"

    transfer_from_priv = setup.b_priv_key
    transfer_from_pub = setup.b_pub_key
    next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_from_pub) + 1

    transfer_to_pub = setup.a_pub_key

    transfer =
      Account.name_transfer(
        transfer_from_pub,
        transfer_from_priv,
        "test.aet",
        transfer_to_pub,
        5,
        next_nonce
      )

    Miner.mine_sync_block_to_chain()

    naming_state_4 = Chain.chain_state().naming

    assert 1 == naming_state_4 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    hash = transfer.data.payload.hash.value
    first_name_transfer = NamingStateTree.get(naming_state_4, hash)

    assert {:ok, first_name_transfer.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_transfer.owner == elem(Keys.keypair(:sign), 0)

    assert first_name_transfer.status == :claimed
    assert first_name_transfer.pointers == "{\"test\": 2}"
  end

  @tag :naming
  test "name not revokable from different account", setup do
    Miner.mine_sync_block_to_chain()
    pre_claim = Account.pre_claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_1 = Chain.chain_state().naming

    assert 1 == naming_state_1 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    commitment = pre_claim.data.payload.commitment.value
    first_name_pre_claim = NamingStateTree.get(naming_state_1, commitment)

    assert {:ok, first_name_pre_claim.hash.value} ==
             NameCommitment.commitment_hash("test.aet", 123)

    assert first_name_pre_claim.owner == elem(Keys.keypair(:sign), 0)

    Account.claim("test.aet", 123, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_2 = Chain.chain_state().naming

    assert 1 == naming_state_2 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    {:ok, claim_hash_1} = NameUtil.normalized_namehash("test.aet")
    first_name_claim = NamingStateTree.get(naming_state_2, claim_hash_1)

    assert {:ok, first_name_claim.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_claim.owner == elem(Keys.keypair(:sign), 0)

    assert first_name_claim.status == :claimed
    assert first_name_claim.pointers == "[]"

    Account.name_update("test.aet", "{\"test\": 2}", 5, 5000, 50)
    Miner.mine_sync_block_to_chain()

    naming_state_3 = Chain.chain_state().naming

    assert 1 == naming_state_3 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    {:ok, claim_hash_2} = NameUtil.normalized_namehash("test.aet")
    first_name_update = NamingStateTree.get(naming_state_3, claim_hash_2)
    assert {:ok, first_name_update.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_update.owner == elem(Keys.keypair(:sign), 0)

    assert first_name_update.status == :claimed
    assert first_name_update.pointers == "{\"test\": 2}"

    transfer_to_pub = setup.a_pub_key
    transfer = Account.name_transfer("test.aet", transfer_to_pub, 5)
    Miner.mine_sync_block_to_chain()

    naming_state_4 = Chain.chain_state().naming

    assert 1 == naming_state_4 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    hash_1 = transfer.data.payload.hash.value
    first_name_transfer = NamingStateTree.get(naming_state_4, hash_1)
    assert {:ok, first_name_transfer.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_transfer.owner == transfer_to_pub

    assert first_name_transfer.status == :claimed
    assert first_name_transfer.pointers == "{\"test\": 2}"

    # fund transfered account
    Account.spend(transfer_to_pub, 5, 5, <<"payload">>)
    Miner.mine_sync_block_to_chain()

    transfer_from_priv = setup.b_priv_key
    transfer_from_pub = setup.b_pub_key
    next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_from_pub) + 1

    revoke = Account.name_revoke(transfer_from_pub, transfer_from_priv, "test.aet", 5, next_nonce)

    Miner.mine_sync_block_to_chain()

    naming_state_5 = Chain.chain_state().naming

    assert 1 == naming_state_5 |> PatriciaMerkleTree.all_keys() |> Enum.count()
    hash_2 = revoke.data.payload.hash.value
    first_name_revoke = NamingStateTree.get(naming_state_5, hash_2)
    assert {:ok, first_name_revoke.hash.value} == NameUtil.normalized_namehash("test.aet")
    assert first_name_revoke.owner == transfer_to_pub

    assert first_name_revoke.status == :claimed
    assert first_name_revoke.pointers == "{\"test\": 2}"
  end
end
