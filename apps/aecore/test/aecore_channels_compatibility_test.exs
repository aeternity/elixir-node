defmodule AecoreChannelCompatibilityTest do
  use ExUnit.Case
  alias Aecore.Tx.{SignedTx, DataTx}

  alias Aecore.Channel.{
    ChannelStateOnChain,
    ChannelStatePeer,
    ChannelStateTree
  }

  alias Aecore.Channel.Tx.{
    ChannelCloseMutalTx,
    ChannelSettleTx
  }

  alias Aecore.Chain.Chainstate

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

    %{
      pk_initiator: pk_initiator,
      sk_initiator: sk_initiator,
      pk_responder: pk_responder,
      sk_responder: sk_responder,
      chainstate: chainstate,
      next_height: 7
    }
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
    epoch_CreateTx =
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
      ChannelStatePeer.initialize(
        <<>>,
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

    assert_txs_equal(data_tx, epoch_CreateTx)

    signed_tx =
      data_tx
      |> chainable_sign_tx(ctx.sk_initiator)
      |> chainable_sign_tx(ctx.sk_responder)

    epoch_channel =
      <<248, 111, 58, 1, 161, 1, 195, 127, 140, 188, 222, 21, 148, 121, 3, 245, 220, 105, 162,
        143, 84, 114, 8, 161, 100, 45, 92, 39, 172, 108, 6, 12, 3, 120, 185, 238, 238, 133, 161,
        1, 246, 50, 15, 95, 253, 247, 7, 8, 114, 192, 202, 92, 31, 249, 69, 161, 170, 113, 41, 30,
        168, 250, 11, 241, 209, 7, 58, 85, 192, 148, 250, 1, 130, 1, 44, 100, 40, 160, 197, 119,
        126, 105, 194, 1, 235, 15, 248, 31, 86, 174, 29, 186, 242, 64, 110, 152, 19, 149, 123,
        111, 63, 231, 79, 148, 218, 78, 165, 165, 37, 21, 0, 6, 0>>

    {:ok, %Chainstate{channels: channels}} =
      Chainstate.calculate_and_validate_chain_state(
        [signed_tx],
        ctx.chainstate,
        ctx.next_height,
        ctx.pk_initiator
      )

    our_channel = ChannelStateTree.get(channels, ChannelStateOnChain.id(data_tx))

    assert_channels_equal(our_channel, epoch_channel)
  end

  @tag :channels
  @tag :compatibility
  test "MutalCloseTx compatibility test" do
    epoch_MutalCloseTx =
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

    assert_txs_equal(tx, epoch_MutalCloseTx)
  end

  @tag :channels
  @tag :compatibility
  test "ChannelSettleTx compatibility test", ctx do
    epoch_SettleTx =
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

    assert_txs_equal(tx, epoch_SettleTx)
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

  defp assert_channels_equal(our, epoch_rlp) do
    {:ok, epoch_channel_decoded} = ChannelStateOnChain.rlp_decode(epoch_rlp)
    assert our == epoch_channel_decoded
    assert ChannelStateOnChain.rlp_encode(our) == epoch_rlp
  end
end
