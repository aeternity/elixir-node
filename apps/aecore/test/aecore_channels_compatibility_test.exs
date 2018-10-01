defmodule AecoreChannelCompatibilityTest do
  use ExUnit.Case
  alias Aecore.Tx.{SignedTx, DataTx}

  alias Aecore.Channel.{
    ChannelStateOnChain,
    ChannelStatePeer,
    ChannelStateTree
  }

  alias Aecore.Channel.Worker, as: Channels

  alias Aecore.Channel.Tx.{
    ChannelCloseMutalTx,
    ChannelSettleTx
  }

  alias Aecore.Chain.Chainstate

  @s1_name {:global, :Channels_S1}
  @s2_name {:global, :Channels_S2}

  setup do
    pk_initiator =
      <<195, 127, 140, 188, 222, 21, 148, 121, 3, 245, 220, 105, 162, 143, 84, 114, 8, 161, 100,
        45, 92, 39, 172, 108, 6, 12, 3, 120, 185, 238, 238, 133>>

    sk_initiator =
      <<4, 150, 12, 249, 87, 125, 35, 204, 27, 94, 230, 114, 50, 190, 72, 5, 56, 51, 232, 248, 85,
        67, 195, 192, 122, 234, 252, 202, 205, 207, 142, 138, 195, 127, 140, 188, 222, 21, 148,
        121, 3, 245, 220, 105, 162, 143, 84, 114, 8, 161, 100, 45, 92, 39, 172, 108, 6, 12, 3,
        120, 185, 238, 238, 133>>

    pk_responder =
      <<246, 50, 15, 95, 253, 247, 7, 8, 114, 192, 202, 92, 31, 249, 69, 161, 170, 113, 41, 30,
        168, 250, 11, 241, 209, 7, 58, 85, 192, 148, 250, 1>>

    sk_responder =
      <<13, 56, 45, 185, 49, 237, 158, 143, 9, 180, 86, 120, 42, 134, 160, 124, 212, 6, 195, 178,
        238, 179, 137, 211, 195, 71, 89, 169, 29, 115, 107, 251, 246, 50, 15, 95, 253, 247, 7, 8,
        114, 192, 202, 92, 31, 249, 69, 161, 170, 113, 41, 30, 168, 250, 11, 241, 209, 7, 58, 85,
        192, 148, 250, 1>>

    chainstate =
      Chainstate.init()
      |> chainable_calculate_validate_chain_state([], 1, pk_initiator)
      |> chainable_calculate_validate_chain_state([], 2, pk_initiator)
      |> chainable_calculate_validate_chain_state([], 3, pk_initiator)
      |> chainable_calculate_validate_chain_state([], 4, pk_responder)
      |> chainable_calculate_validate_chain_state([], 5, pk_responder)
      |> chainable_calculate_validate_chain_state([], 6, pk_responder)

    GenServer.start_link(Channels, %{}, name: @s1_name)
    GenServer.start_link(Channels, %{}, name: @s2_name)
    assert %{} == call_s1(:get_all_channels)
    assert %{} == call_s2(:get_all_channels)

    %{
      pk_initiator: pk_initiator,
      sk_initiator: sk_initiator,
      pk_responder: pk_responder,
      sk_responder: sk_responder,
      chainstate: chainstate,
      next_height: 7
    }
  end

  setup do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  @tag :channels
  @tag :compatibility
  test "Id compatibility test", ctx do
    epoch_id =
      <<241, 22, 174, 6, 3, 175, 147, 100, 202, 226, 36, 81, 132, 3, 60, 40, 171, 173, 182, 207,
        111, 210, 134, 134, 237, 24, 132, 27, 201, 239, 42, 229>>

    responder =
      <<17, 55, 63, 88, 77, 225, 1, 101, 89, 143, 139, 221, 208, 94, 177, 213, 198, 84, 133, 203,
        110, 84, 190, 84, 142, 192, 5, 152, 111, 6, 235, 215>>

    initiator_nonce = 5

    assert ChannelStateOnChain.id(ctx.pk_initiator, responder, initiator_nonce) == epoch_id
  end

  @tag :channels
  @tag :compatibility
  test "CreateTx compatibility test", ctx do
    epoch_create_tx =
      <<248, 111, 50, 1, 161, 1, 195, 127, 140, 188, 222, 21, 148, 121, 3, 245, 220, 105, 162,
        143, 84, 114, 8, 161, 100, 45, 92, 39, 172, 108, 6, 12, 3, 120, 185, 238, 238, 133, 100,
        161, 1, 246, 50, 15, 95, 253, 247, 7, 8, 114, 192, 202, 92, 31, 249, 69, 161, 170, 113,
        41, 30, 168, 250, 11, 241, 209, 7, 58, 85, 192, 148, 250, 1, 129, 200, 40, 6, 0, 30, 160,
        197, 119, 126, 105, 194, 1, 235, 15, 248, 31, 86, 174, 29, 186, 242, 64, 110, 152, 19,
        149, 123, 111, 63, 231, 79, 148, 218, 78, 165, 165, 37, 21, 5>>

    initiator_amount = 100
    responder_amount = 200
    channel_reserve = 40
    initiator_nonce = 5
    fee = 30
    locktime = 6

    {:ok, _statepeer, _id, %SignedTx{data: data_tx}} =
      <<>>
      |> ChannelStatePeer.initialize(
        ctx.pk_initiator,
        ctx.pk_responder,
        channel_reserve,
        :initiator
      )
      |> ChannelStatePeer.open(
        initiator_amount,
        responder_amount,
        locktime,
        fee,
        initiator_nonce,
        ctx.sk_initiator
      )

    assert_txs_equal(data_tx, epoch_create_tx)
  end

  @tag :channels
  @tag :compatibility
  test "MutalCloseTx compatibility test" do
    epoch_mutal_close_tx =
      <<234, 53, 1, 161, 6, 241, 22, 174, 6, 3, 175, 147, 100, 202, 226, 36, 81, 132, 3, 60, 40,
        171, 173, 182, 207, 111, 210, 134, 134, 237, 24, 132, 27, 201, 239, 42, 229, 100, 129,
        200, 0, 30, 5>>

    id =
      <<241, 22, 174, 6, 3, 175, 147, 100, 202, 226, 36, 81, 132, 3, 60, 40, 171, 173, 182, 207,
        111, 210, 134, 134, 237, 24, 132, 27, 201, 239, 42, 229>>

    initiator_nonce = 5
    initiator_amount = 100
    responder_amount = 200
    fee = 30

    tx =
      DataTx.init(
        ChannelCloseMutalTx,
        %{
          channel_id: id,
          initiator_amount: initiator_amount,
          responder_amount: responder_amount
        },
        [],
        fee,
        initiator_nonce
      )

    assert_txs_equal(tx, epoch_mutal_close_tx)
  end

  @tag :channels
  @tag :compatibility
  test "ChannelSettleTx compatibility test", ctx do
    epoch_settle_tx =
      <<248, 76, 56, 1, 161, 6, 241, 22, 174, 6, 3, 175, 147, 100, 202, 226, 36, 81, 132, 3, 60,
        40, 171, 173, 182, 207, 111, 210, 134, 134, 237, 24, 132, 27, 201, 239, 42, 229, 161, 1,
        195, 127, 140, 188, 222, 21, 148, 121, 3, 245, 220, 105, 162, 143, 84, 114, 8, 161, 100,
        45, 92, 39, 172, 108, 6, 12, 3, 120, 185, 238, 238, 133, 100, 129, 200, 0, 30, 5>>

    id =
      <<241, 22, 174, 6, 3, 175, 147, 100, 202, 226, 36, 81, 132, 3, 60, 40, 171, 173, 182, 207,
        111, 210, 134, 134, 237, 24, 132, 27, 201, 239, 42, 229>>

    nonce = 5
    initiator_amount = 100
    responder_amount = 200
    fee = 30

    tx =
      DataTx.init(
        ChannelSettleTx,
        %{channel_id: id, initiator_amount: initiator_amount, responder_amount: responder_amount},
        ctx.pk_initiator,
        fee,
        nonce
      )

    assert_txs_equal(tx, epoch_settle_tx)
  end

  @tag :channels
  @tag :compatibility
  test "Full compatibility test (create, 2xtransfer, mutal close)", ctx do
    # create
    initiator_amount = 100
    responder_amount = 200
    channel_reserve = 40
    initiator_nonce = 1
    fee = 1
    locktime = 6

    tmp_id = <<1, 2, 3, 4, 5>>

    assert :ok ==
             call_s1(
               {:initialize, tmp_id, ctx.pk_initiator, ctx.pk_responder, :initiator,
                channel_reserve}
             )

    assert :ok ==
             call_s2(
               {:initialize, tmp_id, ctx.pk_initiator, ctx.pk_responder, :responder,
                channel_reserve}
             )

    {:ok, id, half_open_tx} =
      call_s1(
        {:open, tmp_id, initiator_amount, responder_amount, locktime, fee, initiator_nonce,
         ctx.sk_initiator}
      )

    {:ok, ^id, open_tx} =
      call_s2(
        {:sign_open, tmp_id, initiator_amount, responder_amount, half_open_tx, ctx.sk_responder}
      )

    epoch_channel =
      <<248, 111, 58, 1, 161, 1, 195, 127, 140, 188, 222, 21, 148, 121, 3, 245, 220, 105, 162,
        143, 84, 114, 8, 161, 100, 45, 92, 39, 172, 108, 6, 12, 3, 120, 185, 238, 238, 133, 161,
        1, 246, 50, 15, 95, 253, 247, 7, 8, 114, 192, 202, 92, 31, 249, 69, 161, 170, 113, 41, 30,
        168, 250, 11, 241, 209, 7, 58, 85, 192, 148, 250, 1, 130, 1, 44, 100, 40, 160, 197, 119,
        126, 105, 194, 1, 235, 15, 248, 31, 86, 174, 29, 186, 242, 64, 110, 152, 19, 149, 123,
        111, 63, 231, 79, 148, 218, 78, 165, 165, 37, 21, 0, 6, 0>>

    {:ok, %Chainstate{channels: channels} = open_chainstate} =
      Chainstate.calculate_and_validate_chain_state(
        [open_tx],
        ctx.chainstate,
        ctx.next_height,
        ctx.pk_initiator
      )

    our_channel = ChannelStateTree.get(channels, id)

    assert_channels_equal(our_channel, epoch_channel)

    # transfer from responder to initiator with amount 70
    epoch_transfer1 =
      Bits.decode58(
        "G6DYbwbT9jsa4M7dKjQAw1bSwcPN3TcaCKtxBBAk28QaXfEugae4HGVNxSHSrSd59vPCLAssWmX8vN48LWwTypFq2FYy8AVAev68Q5WerLhcsCViNAtgNdzdeGhRMYHBHxYwnPdMRjKThcQAogdqjrtnMKnwqVE6awwDPYPmRjsDT3JW8HY8m43SWB9QeiauG3EZx8KnjejyXuNZNPGVjFiGnjQCAhwVb5nPXuhs4KXgTKjB5w1Huch5wJg3HUzyQXhuoCk4gn7vcQvjX7P4rthpo1CMNfJj6WXFowKpVzUCQrVrTYUMHzvbYuymzh1CdcmfgJouxHQmDSHXJwRW6Uw6uwRY192oKMbhsanuLjRJC9YB8SzSLdrSu828c6QLHnWqPedsHwW"
      )

    amount1 = 70

    {:ok, half_signed_transfer_tx1} = call_s2({:transfer, id, amount1, ctx.sk_responder})

    {:ok, fully_signed_transfer_tx1} =
      call_s1({:receive_half_signed_tx, half_signed_transfer_tx1, ctx.sk_initiator})

    :ok = call_s2({:receive_fully_signed_tx, fully_signed_transfer_tx1})

    assert_offchain_txs_equal(fully_signed_transfer_tx1, epoch_transfer1)

    # transfer from initiator to responder with amount 30

    epoch_transfer2 =
      Bits.decode58(
        "G6DYbwbT9jsa4gQAzzxjJuc5AVpowq47hFUNHrtdaU8hn97S1LaKVnE3vp5FW7q9PbXTuP5wwAD9BBHx7WdgfQZw9t7hh5mfS3NNsWHEmBYnyVwodP1EAM4uH3qaaKuNRY1R11VFmRP7zTfcHHU9wssEKFkrLiDqtvK2W9mfcrJFmcFkfLNTQfs633PNbySgQTVW8PG1Fu1F1cahh2kor4HhiDEGBC4xUN6kF2LhhN9w8cMPFYX62QxL1BqmKKzDcbRULXfN6yDnAbd7gKYP53iTNW1quMmMf8wMNr4mCfFwTVdAjsp8LGt2HJ4NitTHe3mmNjD6Vqaoc2CY3S53su7d37ZwJPvKLB5HRa4gmxaRvp1muScA8dNi18GnRmKr8aed7Mpc1NC"
      )

    amount2 = 30

    {:ok, half_signed_transfer_tx2} = call_s1({:transfer, id, amount2, ctx.sk_initiator})

    {:ok, fully_signed_transfer_tx2} =
      call_s2({:receive_half_signed_tx, half_signed_transfer_tx2, ctx.sk_responder})

    :ok = call_s1({:receive_fully_signed_tx, fully_signed_transfer_tx2})

    assert_offchain_txs_equal(fully_signed_transfer_tx2, epoch_transfer2)

    # close mutal

    epoch_mutal_close_tx =
      Bits.decode58(
        "5WatK72bxX5ndWpzzYHAPvg2NQCF4DnUu4F7jMaVCeBTm2FBubskMwhHLDVJUYUkfarQePuoWWrhR25uzfYghn7RhSXsZcLRnNL5LW6Nt1nwsqhjvjRF14Dxm3HSTVjQoMSANeAgLZDfYDNDd7kVeFPpeqBvaNdSv5GK3vk6mkcsfeHQ5tv2wkRtmoJ2McmnzbKjb1tc19BP4XUHNa7wyFD59gNZkaxV7ggdV4vEUjpZC5JSiGEQX8aa8ziLCgFg"
      )

    {:ok, close_tx} = call_s1({:close, id, {1, 0}, 2, ctx.sk1})
    {:ok, signed_close_tx} = call_s2({:receive_close_tx, id, close_tx, {1, 0}, ctx.sk2})

    assert_txs_equal(signed_close_tx, epoch_mutal_close_tx)
  end

  defp chainable_calculate_validate_chain_state(chainstate, txs, block_height, miner) do
    {:ok, state} =
      Chainstate.calculate_and_validate_chain_state(txs, chainstate, block_height, miner)

    state
  end

  defp chainable_sign_tx(tx, priv_key) do
    {:ok, signed_tx} = SignedTx.sign_tx(tx, priv_key)
    signed_tx
  end

  defp assert_txs_equal(our, epoch_rlp) do
    {:ok, epoch_tx_decoded} = DataTx.rlp_decode(epoch_rlp)
    assert our == epoch_tx_decoded
    assert DataTx.rlp_encode(our) == epoch_rlp
    assert DataTx.validate(our) == :ok
  end

  defp assert_offchain_txs_equal(our, epoch_rlp) do
    {:ok, epoch_tx_decoded} = ChannelOffChainTx.rlp_decode(epoch_rlp)
    assert our == epoch_tx_decoded
    assert ChannelOffChainTx.rlp_encode(our) == epoch_rlp
  end

  defp assert_channels_equal(our, epoch_rlp) do
    {:ok, epoch_channel_decoded} = ChannelStateOnChain.rlp_decode(epoch_rlp)
    assert our == epoch_channel_decoded
    assert ChannelStateOnChain.rlp_encode(our) == epoch_rlp
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
