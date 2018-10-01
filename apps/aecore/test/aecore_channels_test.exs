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
    ChannelOffChainTx
  }

  alias Aeutil.PatriciaMerkleTree

  @s1_name {:global, :Channels_S1}
  @s2_name {:global, :Channels_S2}

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

    Miner.mine_sync_block_to_chain()

    {pubkey, privkey} = Keys.keypair(:sign)

    TestUtils.spend_list(pubkey, privkey, [
      {pk1, 200},
      {pk2, 200}
    ])

    TestUtils.assert_transactions_mined()

    TestUtils.assert_balance(pk1, 200)
    TestUtils.assert_balance(pk2, 200)

    GenServer.start_link(Channels, %{}, name: @s1_name)
    GenServer.start_link(Channels, %{}, name: @s2_name)
    assert %{} == call_s1(:get_all_channels)
    assert %{} == call_s2(:get_all_channels)

    %{
      pk1: pk1,
      sk1: prk1,
      pk2: pk2,
      sk2: prk2
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

    assert :ok == call_s1({:slashed, solo_close_tx, 10, 2, ctx.sk1})

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
  @tag timeout: 120_000
  test "Create channel, responder dissapears, solo close", ctx do
    id = create_channel(ctx)

    {:ok, _state} = call_s1({:transfer, id, 50, ctx.sk1})
    assert :awaiting_full_tx == get_fsm_state_s1(id)
    # We simulate no response from other peer = transfer failed

    :ok = call_s1({:solo_close, id, 10, 2, ctx.sk1})

    TestUtils.assert_transactions_mined()

    close_height = Chain.top_height() + 2
    assert ChannelStateTree.get(Chain.chain_state().channels, id).slash_close == close_height

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
  test "Slashing an active channel does not work. Solo closing an inactive channel does not work",
       ctx do
    id = create_channel(ctx)

    solo_close_tx1 = prepare_solo_close_tx(id, &call_s2/1, 15, 1, ctx.sk2)

    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    assert_offchain_state(id, 100, 200, 2)

    solo_close_tx2 = prepare_solo_close_tx(id, &call_s2/1, 15, 2, ctx.sk2)

    # slashing an active channel fails
    slash_tx = prepare_slash_tx(id, &call_s2/1, 15, 1, ctx.sk2)
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
  end

  @tag :channels
  @tag timeout: 120_000
  test "OnChain transaction basic serialization tests", ctx do
    id = create_channel(ctx)

    {:ok, initiator_state} = call_s1({:get_channel, id})
    perform_transfer(id, 50, &call_s1/1, ctx.sk1, &call_s2/1, ctx.sk2)
    [channel_create_tx] = ChannelStatePeer.get_signed_tx_list(initiator_state)
    solo_close_tx = prepare_solo_close_tx(id, &call_s2/1, 15, 1, ctx.sk2)
    slash_tx = prepare_slash_tx(id, &call_s2/1, 15, 1, ctx.sk2)

    {:ok, settle_tx} =
      ChannelStatePeer.settle(
        %ChannelStatePeer{initiator_state | fsm_state: :closing},
        10,
        3,
        ctx.sk1
      )

    {:ok, close_tx} = call_s1({:close, id, {5, 5}, 2, ctx.sk1})

    to_test = [channel_create_tx, solo_close_tx, slash_tx, settle_tx, close_tx]

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
    assert :ok == call_s1({:initialize, tmp_id, ctx.pk1, ctx.pk2, :initiator, 10})
    assert :ok == call_s2({:initialize, tmp_id, ctx.pk1, ctx.pk2, :responder, 10})
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

  defp prepare_slash_tx(id, peer_fun, fee, nonce, priv_key) when is_function(peer_fun, 1) do
    {:ok, state} = peer_fun.({:get_channel, id})
    {:ok, _, slash_tx} = ChannelStatePeer.slash(state, fee, nonce, priv_key)
    slash_tx
  end

  defp prepare_solo_close_tx(id, peer_fun, fee, nonce, priv_key) when is_function(peer_fun, 1) do
    {:ok, state} = peer_fun.({:get_channel, id})
    {:ok, _, slash_tx} = ChannelStatePeer.solo_close(state, fee, nonce, priv_key)
    slash_tx
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

  defp get_fsm_state_s1(id) do
    get_fsm_state(id, &call_s1/1)
  end

  defp get_fsm_state_s2(id) do
    get_fsm_state(id, &call_s2/1)
  end
end
