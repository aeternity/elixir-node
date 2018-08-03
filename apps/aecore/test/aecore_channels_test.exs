defmodule AecoreChannelTest do
  use ExUnit.Case
  require GenServer

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Keys.Wallet
  alias Aecore.Channel.Worker, as: Channels

  alias Aecore.Channel.{
    ChannelStateOffChain,
    ChannelStateOnChain,
    ChannelStatePeer,
    ChannelStateTree
  }

  alias Aecore.Channel.Tx.ChannelCloseSoloTx

  alias Aeutil.PatriciaMerkleTree

  alias Aecore.Tx.{DataTx, SignedTx}

  @s1_name {:global, :Channels_S1}
  @s2_name {:global, :Channels_S2}

  setup do
    Code.require_file("test_utils.ex", "./test")
    Chain.clear_state()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)

    pk1 = Wallet.get_public_key("M/1")
    pk2 = Wallet.get_public_key("M/2")

    for _ <- 1..5, do: Miner.mine_sync_block_to_chain()

    TestUtils.spend_list(Wallet.get_public_key(), Wallet.get_private_key(), [
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
      sk1: Wallet.get_private_key("m/1"),
      pk2: pk2,
      sk2: Wallet.get_private_key("m/2")
    }
  end

  @tag :channels
  @tag timeout: 120_000
  test "create channel, treansfer funds, mutal close channel", ctx do
    id = create_channel(ctx)

    # Can't transfer more then reserve allows
    {:error, _} = call_s2({:transfer, id, 151, ctx.sk2})

    {:ok, state1} = call_s1({:transfer, id, 50, ctx.sk1})
    assert :update == get_fsm_state_s1(id)
    {:ok, signed_state1} = call_s2({:recv_state, state1, ctx.sk2})
    assert :open == get_fsm_state_s2(id)
    {:ok, nil} = call_s1({:recv_state, signed_state1, ctx.sk1})
    assert :open == get_fsm_state_s1(id)

    assert 100 == signed_state1.initiator_amount
    assert 200 == signed_state1.responder_amount
    assert 1 == signed_state1.sequence

    {:ok, state2} = call_s2({:transfer, id, 170, ctx.sk2})
    {:ok, signed_state2} = call_s1({:recv_state, state2, ctx.sk1})
    {:ok, nil} = call_s2({:recv_state, signed_state2, ctx.sk2})

    assert 270 == signed_state2.initiator_amount
    assert 30 == signed_state2.responder_amount
    assert 2 == signed_state2.sequence

    {:ok, close_tx} = call_s1({:close, id, {5, 5}, 2, ctx.sk1})
    {:ok, signed_close_tx} = call_s2({:recv_close_tx, id, close_tx, {5, 5}, ctx.sk2})
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
  test "create channel, transfer twice, slash with old, slash with corrent and settle", ctx do
    id = create_channel(ctx)

    # Can't transfer more then reserve allows

    {:ok, state1} = call_s1({:transfer, id, 50, ctx.sk1})
    assert :update == get_fsm_state_s1(id)
    {:ok, signed_state1} = call_s2({:recv_state, state1, ctx.sk2})
    assert :open == get_fsm_state_s2(id)
    {:ok, nil} = call_s1({:recv_state, signed_state1, ctx.sk1})
    assert :open == get_fsm_state_s1(id)

    assert 100 == signed_state1.initiator_amount
    assert 200 == signed_state1.responder_amount
    assert 1 == signed_state1.sequence

    {:ok, state2} = call_s2({:transfer, id, 170, ctx.sk2})
    {:ok, signed_state2} = call_s1({:recv_state, state2, ctx.sk1})
    {:ok, nil} = call_s2({:recv_state, signed_state2, ctx.sk2})

    assert 270 == signed_state2.initiator_amount
    assert 30 == signed_state2.responder_amount
    assert 2 == signed_state2.sequence

    slash_data =
      DataTx.init(
        ChannelCloseSoloTx,
        %{state: signed_state1},
        ctx.pk2,
        15,
        1
      )

    {:ok, tx} = SignedTx.sign_tx(slash_data, ctx.pk2, ctx.sk2)
    assert :ok == Pool.add_transaction(tx)

    TestUtils.assert_transactions_mined()

    assert ChannelStateOnChain.active?(ChannelStateTree.get(Chain.chain_state().channels, id)) ==
             false

    assert :ok == call_s1({:slashed, tx, 10, 2, ctx.pk1, ctx.sk1})

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
  test "create channel, responder dissapears, solo close", ctx do
    id = create_channel(ctx)

    {:ok, _state} = call_s1({:transfer, id, 50, ctx.sk1})
    assert :update == get_fsm_state_s1(id)
    # We simulate no response from other peer = transfer failed

    :ok = call_s1({:solo_close, id, 10, 2, ctx.sk1})

    TestUtils.assert_transactions_mined()

    close_height = Chain.top_height() + 2
    assert ChannelStateTree.get(Chain.chain_state().channels, id).slash_close == close_height

    {:ok, s1_state} = call_s1({:get_channel, id})
    {:ok, settle_tx} = ChannelStatePeer.settle(s1_state, 10, 3, ctx.sk1)
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

  defp create_channel(ctx) do
    assert PatriciaMerkleTree.trie_size(Chain.chain_state().channels) == 0

    tmp_id = <<123>>
    assert :ok == call_s1({:initialize, tmp_id, {{ctx.pk1, 150}, {ctx.pk2, 150}}, :initiator, 10})
    assert :ok == call_s2({:initialize, tmp_id, {{ctx.pk1, 150}, {ctx.pk2, 150}}, :responder, 10})
    {:ok, id, half_open_tx} = call_s1({:open, tmp_id, 2, 10, 1, ctx.sk1})
    assert :half_signed == get_fsm_state_s1(id)
    {:ok, id2, open_tx} = call_s2({:sign_open, tmp_id, half_open_tx, ctx.sk2})
    assert :signed == get_fsm_state_s2(id)
    assert id == id2

    TestUtils.assert_transactions_mined()
    assert ChannelStateTree.get(Chain.chain_state().channels, id) != :none
    assert ChannelStateTree.get(Chain.chain_state().channels, id).lock_period == 2

    TestUtils.assert_balance(ctx.pk1, 40)
    TestUtils.assert_balance(ctx.pk2, 50)
    assert :ok == call_s1({:opened, open_tx})
    assert :ok == call_s2({:opened, open_tx})
    assert :open == get_fsm_state_s1(id)
    assert :open == get_fsm_state_s2(id)
    id
  end

  defp call_s1(call) do
    GenServer.call(@s1_name, call)
  end

  defp call_s2(call) do
    GenServer.call(@s2_name, call)
  end

  defp get_fsm_state_s1(id) do
    {:ok, %ChannelStatePeer{fsm_state: fsm_state}} = call_s1({:get_channel, id})
    fsm_state
  end

  defp get_fsm_state_s2(id) do
    {:ok, %ChannelStatePeer{fsm_state: fsm_state}} = call_s2({:get_channel, id})
    fsm_state
  end
end
