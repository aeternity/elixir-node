defmodule AecoreChannelTest do
  use ExUnit.Case
  require GenServer

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Tx.SignedTx
  alias Aecore.Keys
  alias Aecore.Channel.Worker, as: Channels
  alias Aeutil.Serialization

  alias Aecore.Channel.{
    ChannelStateOnChain,
    ChannelStatePeer,
    ChannelStateTree,
    ChannelOffChainTx,
    ChannelTransaction
  }

  alias Aecore.Channel.Tx.ChannelCloseSoloTx
  alias Aecore.Tx.DataTx

  alias Aeutil.PatriciaMerkleTree

  @s1_name {:global, :Channels_S1}
  @s2_name {:global, :Channels_S2}
  @s3_name {:global, :Channels_S3}

  setup do
    Code.require_file("test_utils.ex", "./test")
    Chain.clear_state()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  setup do
    %{public: pk1, secret: prk1} = :enacl.sign_keypair()
    %{public: pk2, secret: prk2} = :enacl.sign_keypair()
    %{public: pk3, secret: prk3} = :enacl.sign_keypair()
    %{public: pk4, secret: prk4} = :enacl.sign_keypair()

    Miner.mine_sync_block_to_chain()

    {pubkey, privkey} = Keys.keypair(:sign)

    TestUtils.spend_list(pubkey, privkey, [
      {pk1, 200},
      {pk2, 200},
      {pk3, 200},
      {pk4, 200}
    ])

    TestUtils.assert_transactions_mined()

    TestUtils.assert_balance(pk1, 200)
    TestUtils.assert_balance(pk2, 200)

    GenServer.start_link(Channels, %{}, name: @s1_name)
    GenServer.start_link(Channels, %{}, name: @s2_name)
    GenServer.start_link(Channels, %{}, name: @s3_name)
    assert %{} == call_s1(:get_all_channels)
    assert %{} == call_s2(:get_all_channels)
    assert %{} == call_s3(:get_all_channels)

    %{
      pk1: pk1,
      sk1: prk1,
      pk2: pk2,
      sk2: prk2,
      pk3: pk3,
      sk3: prk3,
      pk4: pk4,
      sk4: prk4
    }
  end

  @tag :channels
  @tag timeout: 120_000
  test "Create channel, transfer funds, mutal close channel", ctx do
    id = create_channel(ctx)

    # Can't transfer more then reserve allows
    {:error, _} = call_s2({:transfer, id, 151, ctx.sk2})

    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 100, 200, 2)

    perform_transfer(id, 170, &call_s2/1, ctx.sk2, &call_s1/1, ctx.sk1)
    assert_offchain_state(id, 270, 30, 3)

    {:ok, close_tx} = call_s1({:close, id, {5, 5}, 2, ctx.sk1})
    {:ok, signed_close_tx} = call_s2({:receive_close_tx, id, close_tx, {5, 5}, ctx.sk2})
    assert :closing == get_fsm_state_s1(id)
    assert :closing == get_fsm_state_s2(id)

    TestUtils.assert_transactions_mined()

    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0
    TestUtils.assert_balance(ctx.pk1, 40 + 270 - 5)
    TestUtils.assert_balance(ctx.pk2, 50 + 30 - 5)

    call_s1({:closed, signed_close_tx})
    call_s2({:closed, signed_close_tx})
    assert :closed == get_fsm_state_s1(id)
    assert :closed == get_fsm_state_s2(id)

    assert %{} == Pool.get_and_empty_pool()
  end

  @tag :channels
  @tag timeout: 120_000
  test "Create channel, withdraw funds, mutal close channel", ctx do
    id = create_channel(ctx)

    # Can't withdraw more than reserve allows
    {:error, _} = call_s2({:withdraw, id, 151, 5, 2, ctx.sk2})

    perform_withdraw(id, 50, 5, 2, &call_s1/1, ctx.pk1, ctx.sk1, &call_s2/1, ctx.pk2, ctx.sk2)
    assert_offchain_state(id, 100, 150, 2)

    perform_withdraw(id, 50, 5, 1, &call_s2/1, ctx.pk2, ctx.sk2, &call_s1/1, ctx.pk1, ctx.sk1)
    assert_offchain_state(id, 100, 100, 3)

    {:ok, close_tx} = call_s1({:close, id, {5, 5}, 3, ctx.sk1})
    {:ok, signed_close_tx} = call_s2({:receive_close_tx, id, close_tx, {5, 5}, ctx.sk2})
    assert :closing == get_fsm_state_s1(id)
    assert :closing == get_fsm_state_s2(id)

    TestUtils.assert_transactions_mined()

    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0
    TestUtils.assert_balance(ctx.pk1, 40 + 100 + 50 - 5 - 5)
    TestUtils.assert_balance(ctx.pk2, 50 + 100 + 50 - 5 - 5)

    call_s1({:closed, signed_close_tx})
    call_s2({:closed, signed_close_tx})
    assert :closed == get_fsm_state_s1(id)
    assert :closed == get_fsm_state_s2(id)

    assert %{} == Pool.get_and_empty_pool()
  end

  @tag :channels
  @tag timeout: 120_000
  test "Create channel, deposit funds, mutal close channel", ctx do
    id = create_channel(ctx)

    perform_deposit(id, 20, 5, 2, &call_s1/1, ctx.pk1, ctx.sk1, &call_s2/1, ctx.pk2, ctx.sk2)
    assert_offchain_state(id, 170, 150, 2)

    perform_deposit(id, 20, 5, 1, &call_s2/1, ctx.pk2, ctx.sk2, &call_s1/1, ctx.pk1, ctx.sk1)
    assert_offchain_state(id, 170, 170, 3)

    {:ok, close_tx} = call_s1({:close, id, {5, 5}, 3, ctx.sk1})
    {:ok, signed_close_tx} = call_s2({:receive_close_tx, id, close_tx, {5, 5}, ctx.sk2})
    assert :closing == get_fsm_state_s1(id)
    assert :closing == get_fsm_state_s2(id)

    TestUtils.assert_transactions_mined()

    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0
    TestUtils.assert_balance(ctx.pk1, 15 + 170 - 5)
    TestUtils.assert_balance(ctx.pk2, 25 + 170 - 5)

    call_s1({:closed, signed_close_tx})
    call_s2({:closed, signed_close_tx})
    assert :closed == get_fsm_state_s1(id)
    assert :closed == get_fsm_state_s2(id)

    assert %{} == Pool.get_and_empty_pool()
  end

  @tag :channels
  @tag timeout: 120_000
  test "Create channel, make a snapshot by depositing/withdrawing zero tokens, solo close with older state fails, solo close with latest succeeds",
       ctx do
    id = create_channel(ctx)

    perform_transfer(id, 25, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 125, 175, 2)

    perform_transfer(id, 25, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 100, 200, 3)

    # prepare solo close but do not submit to pool
    solo_close_tx1 = prepare_solo_close_tx(id, &call_s2/1, 15, 1, ctx.sk2)

    # deposit zero funds -> this will snapshot the state
    perform_deposit(id, 0, 5, 2, &call_s1/1, ctx.pk1, ctx.sk1, &call_s2/1, ctx.pk2, ctx.sk2)
    assert_offchain_state(id, 100, 200, 4)

    # slashing with old state fails
    assert_custom_tx_fails(solo_close_tx1)

    # try the same trick with withdraw
    perform_transfer(id, 25, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 75, 225, 5)

    # prepare solo close but do not submit to pool
    solo_close_tx2 = prepare_solo_close_tx(id, &call_s2/1, 15, 1, ctx.sk2)

    perform_transfer(id, 25, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 50, 250, 6)

    # withdraw zero funds -> this will snapshot the state
    perform_withdraw(id, 0, 5, 3, &call_s1/1, ctx.pk1, ctx.sk1, &call_s2/1, ctx.pk2, ctx.sk2)
    assert_offchain_state(id, 50, 250, 7)

    # slashing with old state fails
    assert_custom_tx_fails(solo_close_tx2)

    # check if solo close with correct state will work
    :ok = call_s1({:solo_close, id, 10, 4, ctx.sk1})

    TestUtils.assert_transactions_mined()

    close_height = Chain.top_height() + 2
    assert ChannelStateTree.get(Chain.chain_state().channels, id).closing_at == close_height

    {:ok, s1_state} = call_s1({:get_channel, id})
    {:ok, settle_tx} = ChannelStatePeer.settle(s1_state, 10, 5, ctx.sk1)
    assert 50 == settle_tx.data.payload.initiator_amount
    assert 250 == settle_tx.data.payload.responder_amount
    assert :ok == Pool.add_transaction(settle_tx)

    :ok = Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Pool.get_pool()) == false
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 1

    TestUtils.assert_balance(ctx.pk1, 40 - 10 * 2)
    TestUtils.assert_balance(ctx.pk2, 50)

    TestUtils.assert_transactions_mined()

    TestUtils.assert_balance(ctx.pk1, 40 - 10 * 3 + 50)
    TestUtils.assert_balance(ctx.pk2, 50 + 250)
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0
  end

  @tag :channels
  @tag timeout: 120_000
  test "Create channel, make a snapshot by depositing/withdrawing zero tokens, transfer, solo close with latest succeeds",
       ctx do
    id = create_channel(ctx)

    perform_transfer(id, 25, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 125, 175, 2)

    perform_transfer(id, 25, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 100, 200, 3)

    # prepare solo close but do not submit to pool
    solo_close_tx1 = prepare_solo_close_tx(id, &call_s2/1, 15, 1, ctx.sk2)

    # deposit zero funds -> this will snapshot the state
    perform_deposit(id, 0, 5, 2, &call_s1/1, ctx.pk1, ctx.sk1, &call_s2/1, ctx.pk2, ctx.sk2)
    assert_offchain_state(id, 100, 200, 4)

    # slashing with old state fails
    assert_custom_tx_fails(solo_close_tx1)

    # try the same trick with withdraw
    perform_transfer(id, 25, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 75, 225, 5)

    # prepare solo close but do not submit to pool
    solo_close_tx2 = prepare_solo_close_tx(id, &call_s2/1, 15, 1, ctx.sk2)

    perform_transfer(id, 25, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 50, 250, 6)

    # withdraw zero funds -> this will snapshot the state
    perform_withdraw(id, 0, 5, 3, &call_s1/1, ctx.pk1, ctx.sk1, &call_s2/1, ctx.pk2, ctx.sk2)
    assert_offchain_state(id, 50, 250, 7)

    # slashing with old state fails
    assert_custom_tx_fails(solo_close_tx2)

    # make some transfers so the solo_close tx will include a OffChainTx
    perform_transfer(id, 25, &call_s2/1, ctx.sk2, &call_s1/1, ctx.sk1)
    assert_offchain_state(id, 75, 225, 8)

    perform_transfer(id, 25, &call_s2/1, ctx.sk2, &call_s1/1, ctx.sk1)
    assert_offchain_state(id, 100, 200, 9)

    # check if solo close with correct state will work
    :ok = call_s1({:solo_close, id, 10, 4, ctx.sk1})

    TestUtils.assert_transactions_mined()

    close_height = Chain.top_height() + 2
    assert ChannelStateTree.get(Chain.chain_state().channels, id).closing_at == close_height

    {:ok, s1_state} = call_s1({:get_channel, id})
    {:ok, settle_tx} = ChannelStatePeer.settle(s1_state, 10, 5, ctx.sk1)
    assert 100 == settle_tx.data.payload.initiator_amount
    assert 200 == settle_tx.data.payload.responder_amount
    assert :ok == Pool.add_transaction(settle_tx)

    :ok = Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Pool.get_pool()) == false
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 1

    TestUtils.assert_balance(ctx.pk1, 40 - 10 * 2)
    TestUtils.assert_balance(ctx.pk2, 50)

    TestUtils.assert_transactions_mined()

    TestUtils.assert_balance(ctx.pk1, 40 - 10 * 3 + 100)
    TestUtils.assert_balance(ctx.pk2, 50 + 200)
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0
  end

  @tag :channels
  @tag timeout: 120_000
  test "Create channel, transfer funds, transfer back, assert that nonce was bumped, mutal close channel",
       ctx do
    id = create_channel(ctx)
    assert_offchain_state(id, 150, 150, 1)

    orig_state_hash = assert call_s1({:most_recent_chainstate, id})

    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 100, 200, 2)

    perform_transfer(id, 50, &call_s2/1, ctx.sk2, &call_s1/1, ctx.sk1)
    assert_offchain_state(id, 150, 150, 3)

    # ensure the offchain nonce was bumped
    assert orig_state_hash != call_s1({:most_recent_chainstate, id})

    {:ok, close_tx} = call_s1({:close, id, {5, 5}, 2, ctx.sk1})
    {:ok, signed_close_tx} = call_s2({:receive_close_tx, id, close_tx, {5, 5}, ctx.sk2})
    assert :closing == get_fsm_state_s1(id)
    assert :closing == get_fsm_state_s2(id)

    TestUtils.assert_transactions_mined()

    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0
    TestUtils.assert_balance(ctx.pk1, 40 + 150 - 5)
    TestUtils.assert_balance(ctx.pk2, 50 + 150 - 5)

    call_s1({:closed, signed_close_tx})
    call_s2({:closed, signed_close_tx})
    assert :closed == get_fsm_state_s1(id)
    assert :closed == get_fsm_state_s2(id)

    assert %{} == Pool.get_and_empty_pool()
  end

  @tag :channels
  @tag timeout: 240_000
  test "Create channel, transfer twice, slash with old, slash with correct and settle", ctx do
    id = create_channel(ctx)

    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 100, 200, 2)

    # prepare solo close but do not submit to pool
    solo_close_tx = prepare_solo_close_tx(id, &call_s2/1, 15, 1, ctx.sk2)

    perform_transfer(id, 170, &call_s2/1, ctx.sk2, &call_s1/1, ctx.sk1)
    assert_offchain_state(id, 270, 30, 3)

    assert_custom_tx_succeeds(solo_close_tx)

    assert ChannelStateOnChain.active?(ChannelStateTree.get(Chain.chain_state().channels, id)) ===
             false

    assert :ok == call_s1({:slashed, solo_close_tx, 10, 2, ctx.pk1, ctx.sk1})

    TestUtils.assert_transactions_mined()

    {:ok, s1_state} = call_s1({:get_channel, id})
    {:ok, settle_tx} = ChannelStatePeer.settle(s1_state, 10, 3, ctx.sk1)
    assert :ok == Pool.add_transaction(settle_tx)

    Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Pool.get_pool()) == false
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 1

    TestUtils.assert_balance(ctx.pk1, 40 - 10)
    TestUtils.assert_balance(ctx.pk2, 50 - 15)

    TestUtils.assert_transactions_mined()

    TestUtils.assert_balance(ctx.pk1, 40 - 20 + 270)
    TestUtils.assert_balance(ctx.pk2, 50 - 15 + 30)
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0
  end

  @tag :channels
  @tag timeout: 240_000
  test "Create channel, transfer twice, slash with old, delegate slashes with correct and settle",
       ctx do
    id = create_channel(ctx)

    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 100, 200, 2)

    # prepare solo close but do not submit to pool
    solo_close_tx = prepare_solo_close_tx(id, &call_s2/1, 15, 1, ctx.sk2)

    perform_transfer(id, 170, &call_s2/1, ctx.sk2, &call_s1/1, ctx.sk1)
    assert_offchain_state(id, 270, 30, 3)

    export_import_peer_state(id, &call_s1/1, &call_s3/1)

    assert_custom_tx_succeeds(solo_close_tx)

    assert ChannelStateOnChain.active?(ChannelStateTree.get(Chain.chain_state().channels, id)) ===
             false

    assert :ok == call_s3({:slashed, solo_close_tx, 10, 1, ctx.pk3, ctx.sk3})
    [slash] = Map.values(Pool.get_pool())

    TestUtils.assert_transactions_mined()
    assert :ok == call_s1({:slashed, slash, 10, 1, ctx.pk1, ctx.sk1})

    {:ok, s1_state} = call_s1({:get_channel, id})
    {:ok, settle_tx} = ChannelStatePeer.settle(s1_state, 10, 2, ctx.sk1)
    assert :ok == Pool.add_transaction(settle_tx)

    Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Pool.get_pool()) == false
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 1

    TestUtils.assert_balance(ctx.pk1, 40)
    TestUtils.assert_balance(ctx.pk2, 50 - 15)
    TestUtils.assert_balance(ctx.pk3, 200 - 10)

    TestUtils.assert_transactions_mined()

    TestUtils.assert_balance(ctx.pk1, 40 - 10 + 270)
    TestUtils.assert_balance(ctx.pk2, 50 - 15 + 30)
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0
  end

  @tag :channels
  @tag timeout: 120_000
  test "Create channel, responder disappears, solo close", ctx do
    id = create_channel(ctx)

    {:ok, _state} = call_s1({:transfer, id, 50, ctx.sk1})
    assert :awaiting_full_tx == get_fsm_state_s1(id)
    # We simulate no response from other peer = transfer failed

    :ok = call_s1({:solo_close, id, 10, 2, ctx.sk1})

    TestUtils.assert_transactions_mined()

    close_height = Chain.top_height() + 2
    assert ChannelStateTree.get(Chain.chain_state().channels, id).closing_at == close_height

    {:ok, s1_state} = call_s1({:get_channel, id})
    {:ok, settle_tx} = ChannelStatePeer.settle(s1_state, 10, 3, ctx.sk1)
    assert 150 == settle_tx.data.payload.initiator_amount
    assert 150 == settle_tx.data.payload.responder_amount
    assert :ok == Pool.add_transaction(settle_tx)

    :ok = Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Pool.get_pool()) == false
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 1

    TestUtils.assert_balance(ctx.pk1, 40 - 10)
    TestUtils.assert_balance(ctx.pk2, 50)

    TestUtils.assert_transactions_mined()

    TestUtils.assert_balance(ctx.pk1, 40 - 20 + 150)
    TestUtils.assert_balance(ctx.pk2, 50 + 150)
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0
  end

  @tag :channels
  @tag timeout: 120_000
  test "Slashing an active channel does not work. Solo closing an inactive channel does not work. Snapshoting an inactive channel does not work",
       ctx do
    id = create_channel(ctx)

    solo_close_tx1 = prepare_solo_close_tx(id, &call_s2/1, 15, 1, ctx.sk2)

    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 100, 200, 2)

    solo_close_tx2 = prepare_solo_close_tx(id, &call_s2/1, 15, 2, ctx.sk2)
    snapshot_solo_tx = prepare_snapshot(id, &call_s2/1, 15, 2, ctx.sk2)

    # slashing an active channel fails
    slash_tx = prepare_slash_tx(id, &call_s2/1, 15, 1, ctx.pk2, ctx.sk2)
    assert_custom_tx_fails(slash_tx)

    assert ChannelStateOnChain.active?(ChannelStateTree.get(Chain.chain_state().channels, id)) ===
             true

    # solo closing an active channel succeeds
    assert_custom_tx_succeeds(solo_close_tx1)

    assert ChannelStateOnChain.active?(ChannelStateTree.get(Chain.chain_state().channels, id)) ===
             false

    # solo closing an inactive channel fails
    assert_custom_tx_fails(solo_close_tx2)

    assert ChannelStateOnChain.active?(ChannelStateTree.get(Chain.chain_state().channels, id)) ===
             false

    # snapshoting an inactive channel fails
    assert_custom_tx_fails(snapshot_solo_tx)

    assert ChannelStateOnChain.active?(ChannelStateTree.get(Chain.chain_state().channels, id)) ===
             false
  end

  @tag :channels
  @tag timeout: 120_000
  test "create channel, transfer funds twice, submit snapshot, tries to solo close with an outdated state, tries to snapshot with old state, mutual close",
       ctx do
    id = create_channel(ctx)

    # Transfer 1
    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 100, 200, 2)

    # Prepare tx
    channel_solo_close_tx = prepare_solo_close_tx(id, &call_s2/1, 5, 1, ctx.sk2)
    channel_snapshot_solo_tx = prepare_snapshot(id, &call_s2/1, 5, 1, ctx.sk2)

    # Transfer 2
    perform_transfer(id, 170, &call_s2/1, ctx.sk2, &call_s1/1, ctx.sk1)
    assert_offchain_state(id, 270, 30, 3)

    # Snapshot
    channel_snapshot_solo_tx2 = prepare_snapshot(id, &call_s1/1, 10, 2, ctx.sk1)
    assert_custom_tx_succeeds(channel_snapshot_solo_tx2)
    :ok = call_s1({:snapshot_mined, channel_snapshot_solo_tx2})
    assert :open == get_fsm_state_s1(id)
    assert :open == get_fsm_state_s2(id)

    channel = ChannelStateTree.get(Chain.chain_state().channels, id)
    assert channel.sequence == 3
    assert ChannelStateOnChain.active?(channel) == true
    assert {:ok, channel.state_hash} == call_s1({:calculate_state_hash, id})

    # Check if solo close with old state fails
    assert_custom_tx_fails(channel_solo_close_tx)

    # Check if snapshot with old state fails
    assert_custom_tx_fails(channel_snapshot_solo_tx)
    channel_snapshot_solo_tx3 = prepare_snapshot(id, &call_s2/1, 5, 1, ctx.sk2)
    assert_custom_tx_fails(channel_snapshot_solo_tx3)

    # Close channel
    {:ok, close_tx} = call_s1({:close, id, {5, 5}, 3, ctx.sk1})
    {:ok, signed_close_tx} = call_s2({:receive_close_tx, id, close_tx, {5, 5}, ctx.sk2})
    assert :closing == get_fsm_state_s1(id)
    assert :closing == get_fsm_state_s2(id)

    TestUtils.assert_transactions_mined()

    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0
    TestUtils.assert_balance(ctx.pk1, 40 + 270 - 5 - 10)
    TestUtils.assert_balance(ctx.pk2, 50 + 30 - 5)

    call_s1({:closed, signed_close_tx})
    call_s2({:closed, signed_close_tx})
    assert :closed == get_fsm_state_s1(id)
    assert :closed == get_fsm_state_s2(id)

    assert %{} == Pool.get_and_empty_pool()
  end

  @tag :channels
  @tag timeout: 120_000
  test "create channel, transfer funds, submit snapshot, try to solo close with the most recent state",
       ctx do
    id = create_channel(ctx)

    # Transfer
    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 100, 200, 2)

    # Snapshot
    channel_snapshot_solo_tx = prepare_snapshot(id, &call_s1/1, 10, 2, ctx.sk1)
    assert_custom_tx_succeeds(channel_snapshot_solo_tx)
    :ok = call_s1({:snapshot_mined, channel_snapshot_solo_tx})

    assert ChannelStateOnChain.active?(ChannelStateTree.get(Chain.chain_state().channels, id)) ===
             true

    # Solo close succeeds
    channel_solo_close_tx = prepare_solo_close_tx(id, &call_s1/1, 5, 3, ctx.sk1)

    # Assert no payload as the most recent state was a snapshot
    %SignedTx{data: %DataTx{payload: %ChannelCloseSoloTx{offchain_tx: :empty}}} =
      channel_solo_close_tx

    assert_custom_tx_succeeds(channel_solo_close_tx)

    assert ChannelStateOnChain.active?(ChannelStateTree.get(Chain.chain_state().channels, id)) ===
             false
  end

  @tag :channels
  @tag timeout: 120_000
  test "Test channel importing", ctx do
    id = create_channel(ctx)

    for i <- 1..10 do
      perform_transfer(id, i, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
      transfered_so_far = div((1 + i) * i, 2)
      assert_offchain_state(id, 150 - transfered_so_far, 150 + transfered_so_far, i + 1)
    end

    {:ok, initiator_state} = call_s1({:get_channel, id})
    {:ok, responder_state} = call_s2({:get_channel, id})
    tx_list = ChannelStatePeer.get_signed_tx_list(initiator_state)
    assert tx_list === ChannelStatePeer.get_signed_tx_list(responder_state)

    {:ok, imported_initiator_state} = ChannelStatePeer.from_signed_tx_list(tx_list, :initiator)
    {:ok, imported_responder_state} = ChannelStatePeer.from_signed_tx_list(tx_list, :responder)

    assert ChannelStatePeer.calculate_state_hash(initiator_state) ===
             ChannelStatePeer.calculate_state_hash(imported_initiator_state)

    assert ChannelStatePeer.calculate_state_hash(responder_state) ===
             ChannelStatePeer.calculate_state_hash(imported_responder_state)

    assert tx_list === ChannelStatePeer.get_signed_tx_list(imported_initiator_state)
    assert tx_list === ChannelStatePeer.get_signed_tx_list(imported_responder_state)
  end

  @tag :channels
  @tag timeout: 120_000
  test "OnChain transaction basic serialization tests", ctx do
    id = create_channel(ctx)

    {:ok, initiator_state} = call_s1({:get_channel, id})
    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    [channel_create_tx] = ChannelStatePeer.get_signed_tx_list(initiator_state)
    solo_close_tx = prepare_solo_close_tx(id, &call_s2/1, 15, 1, ctx.sk2)
    slash_tx = prepare_slash_tx(id, &call_s2/1, 15, 1, ctx.pk2, ctx.sk2)
    snapshot_tx = prepare_snapshot(id, &call_s2/1, 15, 1, ctx.sk2)

    {:ok, settle_tx} =
      ChannelStatePeer.settle(
        %ChannelStatePeer{initiator_state | fsm_state: :closing},
        10,
        3,
        ctx.sk1
      )

    {:ok, %ChannelStatePeer{} = peer2} = call_s2({:get_channel, id})

    {:ok, _, %SignedTx{} = half_signed_deposit_tx} =
      ChannelStatePeer.deposit(peer2, 10, 5, 4, ctx.sk2)

    {:ok, _, %SignedTx{} = half_signed_withdraw_tx} =
      ChannelStatePeer.deposit(peer2, 10, 5, 4, ctx.sk2)

    {:ok, close_tx} = call_s1({:close, id, {5, 5}, 2, ctx.sk1})

    to_test = [
      channel_create_tx,
      solo_close_tx,
      slash_tx,
      settle_tx,
      close_tx,
      half_signed_deposit_tx,
      half_signed_withdraw_tx,
      snapshot_tx
    ]

    for tx <- to_test do
      serialized = Serialization.rlp_encode(tx)
      {:ok, %SignedTx{} = deserialized_tx} = SignedTx.rlp_decode(serialized)

      assert SignedTx.hash_tx(deserialized_tx) === SignedTx.hash_tx(tx)
      assert deserialized_tx === tx
    end
  end

  defp create_channel(ctx) do
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0

    tmp_id = <<123>>

    assert :ok ==
             call_s1({:initialize, tmp_id, ctx.pk1, ctx.pk2, [ctx.pk3, ctx.pk4], :initiator, 10})

    assert :ok ==
             call_s2({:initialize, tmp_id, ctx.pk1, ctx.pk2, [ctx.pk3, ctx.pk4], :responder, 10})

    {:ok, id, half_open_tx} = call_s1({:open, tmp_id, 150, 150, 2, 10, 1, ctx.sk1})
    assert :awaiting_full_tx == get_fsm_state_s1(id)
    {:ok, id2, open_tx} = call_s2({:sign_open, tmp_id, 150, 150, 2, half_open_tx, ctx.sk2})
    assert :awaiting_tx_confirmed == get_fsm_state_s2(id)
    assert id == id2

    :ok = call_s1({:receive_fully_signed_tx, open_tx})
    assert :awaiting_tx_confirmed == get_fsm_state_s1(id)

    TestUtils.assert_transactions_mined()
    assert ChannelStateTree.get(Chain.chain_state().channels, id) != :none
    assert ChannelStateTree.get(Chain.chain_state().channels, id).lock_period == 2
    assert ChannelStateTree.get(Chain.chain_state().channels, id).delegates == [ctx.pk3, ctx.pk4]

    TestUtils.assert_balance(ctx.pk1, 40)
    TestUtils.assert_balance(ctx.pk2, 50)
    assert :ok == call_s1({:receive_confirmed_tx, open_tx})
    assert :ok == call_s2({:receive_confirmed_tx, open_tx})
    assert_offchain_state(id, 150, 150, 1)
    id
  end

  defp assert_offchain_state(id, peer1_amount, peer2_amount, sequence) do
    assert :open == get_fsm_state_s1(id)
    assert :open == get_fsm_state_s2(id)

    assert {:ok, peer1_amount} === call_s1({:our_offchain_account_balance, id})
    assert {:ok, peer2_amount} === call_s1({:foreign_offchain_account_balance, id})

    assert {:ok, peer2_amount} === call_s2({:our_offchain_account_balance, id})
    assert {:ok, peer1_amount} === call_s2({:foreign_offchain_account_balance, id})

    assert {:ok, sequence} === call_s1({:sequence, id})

    assert call_s1({:most_recent_chainstate, id}) === call_s2({:most_recent_chainstate, id})
  end

  defp get_fsm_state(id, peer_fun) when is_function(peer_fun, 1) do
    {:ok, %ChannelStatePeer{fsm_state: fsm_state}} = peer_fun.({:get_channel, id})
    fsm_state
  end

  defp get_our_balance(id, peer_fun) when is_function(peer_fun, 1) do
    {:ok, peer_amount} = peer_fun.({:our_offchain_account_balance, id})
    peer_amount
  end

  defp perform_transfer(id, amount, initiator_fun, initiator_sk, responder_fun, responder_sk)
       when is_function(initiator_fun, 1) and is_function(responder_fun, 1) and
              initiator_fun != responder_fun do
    assert :open === get_fsm_state(id, initiator_fun)
    assert :open === get_fsm_state(id, responder_fun)

    {:ok, half_signed_transfer_tx} = initiator_fun.({:transfer, id, amount, initiator_sk})
    %ChannelOffChainTx{} = half_signed_transfer_tx
    assert :awaiting_full_tx === get_fsm_state(id, initiator_fun)

    {:ok, fully_signed_transfer_tx} =
      responder_fun.({:receive_half_signed_tx, half_signed_transfer_tx, responder_sk})

    %ChannelOffChainTx{} = fully_signed_transfer_tx
    assert :open === get_fsm_state(id, responder_fun)
    :ok = initiator_fun.({:receive_fully_signed_tx, fully_signed_transfer_tx})
  end

  defp perform_withdraw(
         id,
         amount,
         fee,
         nonce,
         initiator_fun,
         initiator_pk,
         initiator_sk,
         responder_fun,
         responder_pk,
         responder_sk
       )
       when is_function(initiator_fun, 1) and is_function(responder_fun, 1) and
              initiator_fun != responder_fun do
    initiator_onchain_balance = TestUtils.get_account_balance(initiator_pk)
    responder_onchain_balance = TestUtils.get_account_balance(responder_pk)

    channel_onchain_state_initiator_balance =
      ChannelStateTree.get(Chain.chain_state().channels, id).initiator_amount

    initiator_channel_balance = get_our_balance(id, initiator_fun)
    responder_channel_balance = get_our_balance(id, responder_fun)

    assert Enum.empty?(Pool.get_pool()) == true
    assert :open === get_fsm_state(id, initiator_fun)
    assert :open === get_fsm_state(id, responder_fun)

    {:ok, %SignedTx{} = half_signed_withdraw_tx} =
      initiator_fun.({:withdraw, id, amount, fee, nonce, initiator_sk})

    assert :awaiting_full_tx === get_fsm_state(id, initiator_fun)

    {:ok, %SignedTx{} = fully_signed_withdraw_tx} =
      responder_fun.({:receive_half_signed_tx, half_signed_withdraw_tx, responder_sk})

    assert :awaiting_tx_confirmed === get_fsm_state(id, responder_fun)

    :ok = initiator_fun.({:receive_fully_signed_tx, fully_signed_withdraw_tx})
    assert :awaiting_tx_confirmed === get_fsm_state(id, initiator_fun)

    assert Enum.empty?(Pool.get_pool()) == false
    TestUtils.assert_transactions_mined()

    assert :ok == initiator_fun.({:receive_confirmed_tx, fully_signed_withdraw_tx})
    assert :ok == responder_fun.({:receive_confirmed_tx, fully_signed_withdraw_tx})
    assert :open === get_fsm_state(id, initiator_fun)
    assert :open === get_fsm_state(id, responder_fun)

    channel = ChannelStateTree.get(Chain.chain_state().channels, id)
    assert channel != :none

    assert channel.sequence ==
             ChannelTransaction.unsigned_payload(fully_signed_withdraw_tx).sequence

    assert channel.state_hash ==
             ChannelTransaction.unsigned_payload(fully_signed_withdraw_tx).state_hash

    assert channel.total_amount == initiator_channel_balance + responder_channel_balance - amount

    if amount > 0 do
      assert channel.initiator_amount == channel_onchain_state_initiator_balance
    end

    TestUtils.assert_balance(initiator_pk, initiator_onchain_balance - fee + amount)
    TestUtils.assert_balance(responder_pk, responder_onchain_balance)

    assert initiator_channel_balance - amount == get_our_balance(id, initiator_fun)
    assert responder_channel_balance == get_our_balance(id, responder_fun)
  end

  defp perform_deposit(
         id,
         amount,
         fee,
         nonce,
         initiator_fun,
         initiator_pk,
         initiator_sk,
         responder_fun,
         responder_pk,
         responder_sk
       )
       when is_function(initiator_fun, 1) and is_function(responder_fun, 1) and
              initiator_fun != responder_fun do
    initiator_onchain_balance = TestUtils.get_account_balance(initiator_pk)
    responder_onchain_balance = TestUtils.get_account_balance(responder_pk)

    channel_onchain_state_initiator_balance =
      ChannelStateTree.get(Chain.chain_state().channels, id).initiator_amount

    initiator_channel_balance = get_our_balance(id, initiator_fun)
    responder_channel_balance = get_our_balance(id, responder_fun)

    assert Enum.empty?(Pool.get_pool()) == true
    assert :open === get_fsm_state(id, initiator_fun)
    assert :open === get_fsm_state(id, responder_fun)

    {:ok, %SignedTx{} = half_signed_deposit_tx} =
      initiator_fun.({:deposit, id, amount, fee, nonce, initiator_sk})

    assert :awaiting_full_tx === get_fsm_state(id, initiator_fun)

    {:ok, %SignedTx{} = fully_signed_deposit_tx} =
      responder_fun.({:receive_half_signed_tx, half_signed_deposit_tx, responder_sk})

    assert :awaiting_tx_confirmed === get_fsm_state(id, responder_fun)

    :ok = initiator_fun.({:receive_fully_signed_tx, fully_signed_deposit_tx})
    assert :awaiting_tx_confirmed === get_fsm_state(id, initiator_fun)

    assert Enum.empty?(Pool.get_pool()) == false
    TestUtils.assert_transactions_mined()

    assert :ok == initiator_fun.({:receive_confirmed_tx, fully_signed_deposit_tx})
    assert :ok == responder_fun.({:receive_confirmed_tx, fully_signed_deposit_tx})
    assert :open === get_fsm_state(id, initiator_fun)
    assert :open === get_fsm_state(id, responder_fun)

    channel = ChannelStateTree.get(Chain.chain_state().channels, id)
    assert channel != :none

    assert channel.sequence ==
             ChannelTransaction.unsigned_payload(fully_signed_deposit_tx).sequence

    assert channel.state_hash ==
             ChannelTransaction.unsigned_payload(fully_signed_deposit_tx).state_hash

    assert channel.total_amount == initiator_channel_balance + responder_channel_balance + amount

    if amount > 0 do
      assert channel.initiator_amount == channel_onchain_state_initiator_balance
    end

    TestUtils.assert_balance(initiator_pk, initiator_onchain_balance - fee - amount)
    TestUtils.assert_balance(responder_pk, responder_onchain_balance)

    assert initiator_channel_balance + amount == get_our_balance(id, initiator_fun)
    assert responder_channel_balance == get_our_balance(id, responder_fun)
  end

  defp prepare_slash_tx(id, peer_fun, fee, nonce, pub_key, priv_key)
       when is_function(peer_fun, 1) do
    {:ok, state} = peer_fun.({:get_channel, id})
    {:ok, _, slash_tx} = ChannelStatePeer.slash(state, fee, nonce, pub_key, priv_key)
    slash_tx
  end

  defp prepare_solo_close_tx(id, peer_fun, fee, nonce, priv_key) when is_function(peer_fun, 1) do
    {:ok, state} = peer_fun.({:get_channel, id})
    {:ok, _, slash_tx} = ChannelStatePeer.solo_close(state, fee, nonce, priv_key)
    slash_tx
  end

  defp prepare_snapshot(id, peer_fun, fee, nonce, priv_key) when is_function(peer_fun, 1) do
    {:ok, state} = peer_fun.({:get_channel, id})
    {:ok, slash_tx} = ChannelStatePeer.snapshot(state, fee, nonce, priv_key)
    slash_tx
  end

  defp export_import_peer_state(id, from_server, to_server) do
    {:ok, from_state} = from_server.({:get_channel, id})
    tx_list = ChannelStatePeer.get_signed_tx_list(from_state)
    {:ok, to_state} = ChannelStatePeer.from_signed_tx_list(tx_list, :delegate)
    to_server.({:import_channel, id, to_state})
  end

  defp assert_custom_tx_fails(%SignedTx{} = tx) do
    assert :ok == Pool.add_transaction(tx)

    Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Pool.get_and_empty_pool()) == false
  end

  def assert_custom_tx_succeeds(%SignedTx{} = tx) do
    assert :ok == Pool.add_transaction(tx)

    TestUtils.assert_transactions_mined()
  end

  defp call_s1(call) do
    GenServer.call(@s1_name, call)
  end

  defp call_s2(call) do
    GenServer.call(@s2_name, call)
  end

  defp call_s3(call) do
    GenServer.call(@s3_name, call)
  end

  defp get_fsm_state_s1(id) do
    get_fsm_state(id, &call_s1/1)
  end

  defp get_fsm_state_s2(id) do
    get_fsm_state(id, &call_s2/1)
  end
end
