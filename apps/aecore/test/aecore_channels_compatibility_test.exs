defmodule AecoreChannelCompatibilityTest do
  use ExUnit.Case
  alias Aecore.Tx.{SignedTx, DataTx}

  alias Aecore.Channel.{
    ChannelStateOnChain,
    ChannelStatePeer,
    ChannelStateTree,
    ChannelOffChainTx
  }

  alias Aecore.Channel.Worker, as: Channels

  alias Aecore.Channel.Tx.{
    ChannelCloseMutalTx,
    ChannelSettleTx
  }

  alias Aecore.Chain.Worker, as: Chain

  alias Aecore.Chain.Chainstate

  alias Aeutil.Bits

  @s1_name {:global, :Channels_S1}
  @s2_name {:global, :Channels_S2}

  setup do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()
    tests_pow = Application.get_env(:aecore, :pow_module)
    Application.put_env(:aecore, :pow_module, Aecore.Pow.Cuckoo)

    on_exit(fn ->
      TestUtils.clean_blockchain()
      Application.put_env(:aecore, :pow_module, tests_pow)
    end)
  end

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
        {:sign_open, tmp_id, initiator_amount, responder_amount, locktime, half_open_tx, ctx.sk_responder}
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

    assert :ok == call_s1({:receive_confirmed_tx, open_tx})
    assert :ok == call_s2({:receive_confirmed_tx, open_tx})

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

    #FIXME assert_offchain_txs_equal(fully_signed_transfer_tx1, epoch_transfer1)

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

    #FIXME assert_offchain_txs_equal(fully_signed_transfer_tx2, epoch_transfer2)

    # close mutal

    epoch_mutal_close_tx =
      Bits.decode58(
        "5WatK72bxX5ndWpzzYHAPvg2NQCF4DnUu4F7jMaVCeBTm2FBubskMwhHLDVJUYUkfarQePuoWWrhR25uzfYghn7RhSXsZcLRnNL5LW6Nt1nwsqhjvjRF14Dxm3HSTVjQoMSANeAgLZDfYDNDd7kVeFPpeqBvaNdSv5GK3vk6mkcsfeHQ5tv2wkRtmoJ2McmnzbKjb1tc19BP4XUHNa7wyFD59gNZkaxV7ggdV4vEUjpZC5JSiGEQX8aa8ziLCgFg"
      )

    {:ok, close_tx} = call_s1({:close, id, {1, 0}, 2, ctx.sk_initiator})
    {:ok, signed_close_tx} = call_s2({:receive_close_tx, id, close_tx, {1, 0}, ctx.sk_responder})

    assert_signed_txs_equal(signed_close_tx, epoch_mutal_close_tx)
  end

  @tag :channels
  @tag :compatibility
  test "Blocks compatiblity (create, mutal close after transfer)" do
    blocks =
      Enum.reverse([
        <<"DR2T7eG467Zmy3mtr3AT6TnDLcoBD3sCtjpjzSuJQ7XMWpGiNUmUAsam58wMUoh3ino74fsqZn4bPpW1WK39WjtwU46zvtfApntS2hikUFWPCwYdHNPju47PdTYvr7atrEF6ANvsY3SVjsVow67xKFNMYUCQLMdrEo3yp5Kcxpp6Psah7uq6aM2Y7bTiFBAtqLWvbgToXLVTFPpeE7utePJbGM79Z5cZVXaNjbTantk3zzxg8BHhRC2GwPoUPABc2PZ8veg8CtgRU5sRuzDfDRjbKxZg7VcjY9Fnqp4iEEEooYhBFix9eeApqzESQAyN9JCb75y8FWx89LsaX4QBrsXLNKpz7k54c1XC5ooUmbQqK84GpD73JojxreCePaMh2a6jRAJVQAEdKVsYL64x4bmHbY7HYAr4VdFRwdwLAUBCcSYtwMoDqxNDYugVcTVkU7t3Ree4v9Li9buDg3pZ6w5awghhdHTWJLmAV7MGnChWuHSbcM3tkQMZLmVHhG4LQQtx3U9EPBM9RpMoQKYmLMgVhPETu337DUaru6Rf9vo4SwPxUpXmkSTn9STtYgxSTKPJhEmQ8HNa8Nju7zTmBiXG8A3C5ZaeTe6B5pjBrrs19XfpV1FY6FAYNo3mLGsucHtuAaLGT7PbSAVc2WLo3RHA3EcLbfq9d3u6viof4ANsZ4kYtVHNFY4yUADqVNSR35seAFh59JsM5gc6kuSFJVwfA3G">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutrSMivaY6CgedtHQhEeaEsoMDobDTwUCqfXnGvmxCx49qtwFbGHmbQJ9W6wRjhuKhYw6KMLhL88M2yCTbcPjNQRaQD9EzLKU5sKmgXzgPW1p2MwT967DwsA11rUHLhEV7hrZY9H33sWs2X7L4iM2k4YiDAJTE4tReJou2YKeN1Gy9DWVhqN8vqoXhdNJH9yNjr1typhRaUi64tnqGp6MaEVmuFEAJ8u1B2iu71YY62oZVBppAweBu6iKk9kK32gxqZPLV5xWVayfpNUJRrQyMWmcjgfv6ag8LHZDmUgpWzrAhbn1qMatyeud8PGQEeJwvMizEnJDWkUmk86WjDmocup56gqM6u4xUM79DA5h6tkzsLTbfEoE6ZoSZt7iM6NqvkbmwtkPMX3saGyHNhzTTEWt5qkj2HgZeMBfVaUgcZSs8diUXT6modpKS8M3Gy">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutqgD4rmfrn45hqeTh7aDjf6mpcbAZAtTdNbWJSGwz2DBAnpqxAYBnF6J3m45Uwp1TGWtUPDYBayQCNDqspMD3eCSSHJHpFjqf6L8HomLxL5Je6UkwykWR6SwUSHVpqzxAjEwTXMq5WkJ4A4Hri5Q6JJss2da72ToQRdZRqqS4PyHpQo4T8Hv1PYTKYzWDNC3Lvf6qjR6atVPHhMoCGd8TqMsJdCwbvTK9QY8vtEhw1MSWNnQaA8oDuHwSrVEZSePduyo4HAfmJzG2rTy9q7xMHX4Ljv238YZNv8aHGS9fqm7ur3BMBU8QPtKc837zo9XeaLFz4Pn5DsV3zB6AvcLRbA7dHCZvEhfVuvjyDz7gzAnkgY6WYb8yfsPNs8k4hrrGh62UxJ8fYvifWSpFsZbsGAmZX9tadtFxNY6e4T3boHqjExC4YbgHjdWtiqVQ5">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutqHcWeTGfCbQ7m2o8pRc8qTCqACjaeomGiaprtsCERXXCvbdbyZZzY1dgcvazYfN2hp3JV3TABLkMJ8MXFgE5RCVgi2XFwrfaC9x2qTdfhxXfpG8Waj5BUDAhRuUonMtuaK9SS3QztppzvJka4KFkFxYmJcvjZMj36ooojpHeJsRWN8enAiX4LEzoA8mnCeU1hk3M5dnbCLHMyerQYnYeuS7y7QTJN5SnTgBUvAJkwUB8wFzhh2jnc3CrnMf3epVrxaTR1kJ8SXBHBsdoSEkjaAFG5tov8bCWQwQsAHayWuWTch5uWCAshQoaUHf5mzeCr9QmfjvB6s9QhAbSFA6BeHA2yzsaSy8nTtLCeaBvomPLXTNEZXHUxEDRLuKxsH3dKidpq9mHNWrtVUWhARkzewv1zamJ1SytA6t51AzAcKizNmqSzzPecM47LtX3t">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutpx6Rii96VKcMCUAy3UFEztzhTgM7qwS22FftPZfkGtHPkZ21DKxNckrchGn1Mv7Bi79rWko1HGuj7WDbA7tE72C2Bn57zL1kf7fvxTP4GRaNHc9a86336VWzMwPt2fbzA5GecYATdzcKxCqhdT27aCUr6ehG7Q8Km7zoM7Cus2gXorMwpg9AnUHDjyN8NDycBR9a97i6kZGU2kP4sYyZTFM8dnSwrNJDacLSy73ew8Z1ezQMWobwv4VTVEnhVsBqe9AbeApncUR7qBZtKU2pJU3aWN69GQvTkPrynJfsccGiHh1WDoE6W2xe5kLZM83xkMPMiq2ZTeC63zYMHz2r98bVVyF5SrADANWTKtZA1xvWC7UPzAfRoJDP5qe8u7eP5R9ujXznaJjccvT3CbgyYxp7oLBpYA3dmJbFXTE5NQ8sitY34Dp6iHAywBEGE">>,
        <<"3Qf3pVdBGy8PrWGF5wPMD9JF5vazUKS1NfRwYrYpfYf5TTxg5Qpw4MjDf3y5Gr2xZgY8JrsH9xZ6v12ZJquqdccRQ3WJFfS7Cb4956DjSMSVVAhqsice8ybpGqoXrNbLaUtgNGP6wUxRfBDMVSztFPgvqqy6SSVBLeqt7smfL15W8r65S2nSXSxDR3rxPEpbA79ZfygGuSpyFDmLnWxxHsEU3R9tFHwNksazfAhSq4JwwaDsfZH6XYZuz5tdjdSRD1Cnv53HjvgC9bCgNE7dqBuqdU218ztD4QAG8mdmqZ6ig6FbngKHifaD2EL2Fty5BSu29GC1g2gEA8AWsXUhdvK6xf9ACVY7wgH1KgznYziMcxKm4Z194V4wisMXeVARfSGrBesPdDRizvUhon5i3dWmTYDM6M33NyCUyzP9FpGLRmHtKzTFuKqH2XvHSAX4WtSmuBFxKX5EHbJPdsh9aeyTyJvjjZNY3LrgAniKAi4TiTixAMVb7wWsohXXjCRs2WvvkwDipoHXNrS1GnVmEyt9bN94exY8RArALH7AqTrEio3b2ig6EqJuwEnpS3yEGwsNPTFuBBC54zdtND8ibnvB5ULaWo8xcA1AAgy7v6HTf83xnJzSBU7onBdghyN2Z64VAjfjtSyhDjAmfCXcCFwY1cauUbfEELyWYv5zMPdZe3rvahdKzFAh44Kwkppfc2U6pfmauF9HsZLh3gDmLsBuUYQQ6j96mjxrQL82wPswFM1UvM5dDiFBVxW1N1NzUgxmaWRZCVgHZCFHcnebD5kjjhoFeWcRFxCv5Qe5F2q2JsdZ6Tc9aBeU5hG">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutoj2yoMmssBCXaJamyEqxxn1qG8qUwxZ4BEstABFNTSxmUGMCsxnyh3FS37ZcZKM8XrXTitZXupzqMHXXTcQ4kzyPa975j1eX3Whdedtz2NHbac8id4S5eGuSr2Ej53LLBq2u9zwucD71MpD1YQTKDC4jS8qXQect1nAtSUW8riyMiok5yjDaNxiiDEnRFaBsoMhV2w16DWNXpygqSc9nzhqRdKBG2uJjZcsd9cJTCgaEiUaFSe1GuAya1RuDCwbgkAqfbY4pBLjuu7Fzf482EdD4RURUwCQJjiBRAHBaRmuuauezdN4ydyoVHtTgAzzPFfcBkoTS5dY5yH5SeSuQn6tY2TufEtQkPC2UtejBrsh3gKJEbkrsDEPqHapGMdNFXggmLn5tvdUcyj7SGKTnTGCruZiaMdgo1bswFJtCvDRq41rWJKgZhr9Gc9yf6">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkuto9pSrbTW4dkpS91AFEhM7CyKeCUkcCYFcpTxwurG7XswPPerUjbMvadB7MtvHDGdxYRkfL6NpY6ofxLwb9ufcYzy2R3qzjdpV48XsisB2c1Si7MgPcL7Yb13iPc6qF3mCFekqZZXVVTx43HWitdsioqQbgtakkTg7EpJVcJS7xHPqCE2jyHQb6rjmyyDrbANpGjd3aKXw1jsYWcqri6pXEPyQd3hzux3C6MECRBZ44VNSTSef5TWLXb3f8cYka6eJXgzmxnsv3UQE6TerikbTshgq7mEnMtm2BTd7QkHjgHRYQqYes1hTyXryoPBTADH3mBTpBWCxbk7FmcYLD2ywKfEXkVZCuP5BjBmH8oAeP3XC5ysPRXAXiMAQYWfLVrFHRtkPCUgefEcYDimMDAmnqNhVDVCuP88c7jmP7vMbb9ir3j71na6kDgWdG5Bn">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutnSrSz7F9dRY239WK9T1SGCxGG1oJUAqwYvoYJ51hk1Z6tsSHevD4wMGv328idz8LA9S89Yhd4ckuVH5PQqcBxTBtqbZCEzxfmbdVvCGLngQ19KHdVoCefomrHmG1Rc7BtCYj7ba8dwCjGn8x26MrCZmpq1N1N5ALm2HDKAGHQgRGqME4UxXw4cVJtgL58mhLiSrr1qxrtGh5TxU6GMHFHaiVoi3FreQkNtXmZBu11bvudqRLDGB7Yy9bZGY841dJKzECQwEf1L2epQJ4KGFdbMRtsRGGSg71m2FD6YsuhUpPH4jhQxL5kVb7atnURhGFZfeGFEHDRco9xZvbU15jUf1392n9Ap8Zf35ZFs7mXvDKP4wYTvzXYou1mYPAQpmJw6Aakcd8JSq1v2idciXjsZV2zX9xihxeJ2x8XNrtQET7HAyKrY2oVwHkVMGHN">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutmxDayQ9Y7YSrTd5JwWboK9rHuMtaBvPuJtZLffDWMExrac1svCXism8MVo8NEwSbKiMH2ZMwqh8gSBoFvKC5bhibnjKgeEvz9kazdWACkke2DnMhqrE8DNzB9YvKiq4R4qbG4LdDX4Lg7oULQgYqinjWHNWCfufAxnCSKVHgiykJN5LtHmmXcpsGa66R1zGadWPnBYFrs1mesisMwFk6JSuoEDLsaDFpnvkqh2Gg9ZcMDLrp2VSuc2etcqQB4pE9L8oXpmtzUr9JB6U1My1JEFQRmY13oypFHifgeuqFwe3mo7qSkNA4EwD9CynAfCdHrJvgAhqKEFfKjiFgZYG4FC3xVACS4ybAp7noEU4MqpAGEjussQGQo6o8hxRhuvMsaakaWsbiHh8k3UAbTvNcV5LC2b5weNkW6WwZTyi6tyNifMirr2V9qdt7vVXjF">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutmMcd9xviSb8h5LLThVBg4B8jFZcCK5jQBDDSUjYw7xj4DJgERvw4R9WrooQwdG8jT6gAdYLn8zs1thKpPmyjTmobLQTQHuygUhuktQ3kW1YhsQ2p1YnPJc4rPXuwBbViCZ9uhCR3wujkwa7UyD2APgrW26cmtRFhXPKCLsKqb57mtHsxYtcyMQjPXHgMCxC7hP7BjHBew7SbYbx5e573a9aHvtH1ziH37cTLttJw2VbXA2guwwrYFGgE4UEbVT9p2XcKsZGFLh9TUzR2gxLV2RzAU2ucxQD23VtBGxaGc9TomVgWsmQQ2qvMhp6v8muHne8gEsodT5WUHxTvP2y3D7425akkzHa5qDWrFGCtbzh8uqoHPXYL43TpDcvMe8WzMuK6otAt2bsMCmxu6ZPaxpDaZfAQtUXCVnhYCPYERBimyBs22bTLrkwDJ3ezY">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutmCr7ZNyhRFDSMUaTsGQPBRgToosCHuPuZb7VbVtRPt9diUZtY274CBdgTx7bCipKewu8UN9EavtTCHFQN4FXJZTRmrJj16W3ZHjJoSf1H33CA9PyhbSxZ5tGX9SNxD3K14EQuTdYpeqiVaCWbibGJHC3w7ZHxGAKnnBDKZhREH2bzQGhFKc9N4vMstZ36R8mxkU3K1wFjKQCxUvPc7fxxveQ24hFUTNaVL6CYLvRrG29GwHNbcFPBeBBQxGTfSHgp4ciU6DFwtfwQTJL1aJwatPwvvPBydm4YZ1PHhZfN4Lw3UtemPW1kL7vpGmNm3H4tf8xZrZDvjYzRVD62GmpyD2pXvAuBza43SaCjnreCwjMb2NhoUSnYLyY7xNwbHd3QA5sp19u17ti7NuzDuw3Tzx6bcWUaZkh3YbZxrTsYcVNEnwYyFvVfu2a9f74P">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutkWe34FRNr433X56Tes11u4LMXPFqeXe1R69Rd1MHEpBaHbTZgFPbwXeAPPGD3pMzao4aoRC7GiY7EHx1HSAVkU463nyzpjXN4K3eH1YKKhYHzCxxxoztkhhxBDH96PqWTV67avZRSfuEJaj6bZKdg7twYFShDsX4fJcMquCN6yhcb3j5k8eEz3ECctZYXXMSah9FghnYLYLhp4XdDvzhxh2YobRJXh9DQ1j2zcXkT9xnPL9Zsftr7RpQS13TisSMuEcUcCApqTHCxggrPf3FFKPjGfqkvU6E1ow8rvRcWYzGaX48rFaT7fzQxkAEbKthymugevskZnhfak4cfAxE1VXqniNjL46KHfpYdn7325ntiM7t43cNTLmDT9g76t2iGyjFQnxVVAPKSSNUzVc7aLHXFN1VszaBbpu8iarvWNy8WX1QfkCM4ELRDQYSA">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutjtJmV1c74QTSfaAG9rmTeqsLQVirDqhy2G16Ee4kkyVnoYKEbreWCYFHbhvzmbgjisGZ866yfcLfD3r1PfKxJMkVveVPProTAEJQwTenoa6sHDy4mjmck4qHPfDiWPtN6FR96isnE6WoSyMm1dSWebZmv9f6kSy9wfJT1W7yBQE9oYan9fGsXCtxN45f9xRwLqxBGLujr3i5EXXbBnm944z2SNPmtQijS2CyeTEBHxHNrKXCpi6GPe9aFMC6Dva3AQ7o3nS8iSyAF12g7vU98iLC35mzSCdjVACAqvPc8Uhk9RNFT2oM51UAcAxmWoxMCuH5zWbiKXsoLHaDxX6mmiMNA7MNkKfc4wSimTFQHU6ZqG1G7tdz7Y5MzPTsgzVY2zAyx1Cv1HvkK2zZN6DYuwPEgJGRqCdpHjsRoqAgoj5yieHT7t3kW8dQwZPLD">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutjJUKARiG64F5DUofdnSt9zHqEJ1HE5D6Pqi2hNLoFCJAnrMcJd1w52pC6B4Vuj8v6LQm2KXSP3qrtsovPHbRqxyagsG2mpkGBEeHEMC4rYVzHtgJKXcQ1hGHGtGdkUYF5NzjGRDVp998y7NFh2A8rv1skjjEvXzykMerJ2f9EoULo6zL3BWUyJY6r3ApiJtDKKRedEXE7PRrXdWf7FCiwTKop5DGbQrTR1Zn84E3F4pHAkXzYPWM8hvd55a6hYoM1B7ddwMieCMxac5L1tKhiD8hfRZy8QNBeGx3P3SGMbW9irVcpbBuowZBtKX22fiDz4saqU5MTbrn4KKYHTSjWznmmrBAqKWBuWi5wrwkz3dFdCfgLryxXPbWFTVaY5gH6giMKFqzXhquANfh8oxGfjQmCz1ZFp56AoCyX9uA2f1Qm61oPr6xiQu9Cpb53">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutj1PVVse8sTrxd3Cf27tDYx9iNYpPnS5gB9csJYheAXTkqG7ECYJJynpDEaLEzMDs7fyb9UUFmb8XkZwuc3VmUJ3ZuMS7EMBqjFCu4tdgUGpuyNT5qyKgXo7QhqSFDaetXgjRHbo7XVtXyGUcYhSsDk2SPxtEMRWze4rvgyy5Rd7e9NWzuDyQXH2dGEPXQU8uRzJXikUHteCu8CZtsBYgSvBYfuxUj5E5CEmxi8HrajETaAjPEovPCKwEGCVxzygDjesUvcn1KRpi5zHVHNBy5QyLTj4XY494No7JjjkhtjLTAfKtRP3Pa4GpS31dVE3cZXYVCuhxqVdViHZvY1rdEDxrXB15HCukgYb59TajFt3x2mXsjxEwfLh78GqmgBBsDHdfpNsCHjuzZcin3bHTjoL5foF54YGaKqDcTmGKhufdwBYT4XKze4HKUWAKU">>,
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutikLVdAqrqvqaquwLnGqTNoU8jy8ndyxwxsVTr2JJsRgFctDoC6Ccxfnq8fsCL2hsnWB4xshaBquFUb1WjhibGjwEqGK25kdQ5MeCZZH14fP6S1PkLa4h8trtnPhjzR8LgPrSZoHpjP7HW92q3K612zsQL8XqLyiMhX69dAHoxtJBKXg9MZaFWEuWPnTis7kuKMGmnhHN1YdjVYWKKpZynNyQ1rQ8fJzHczJ5jWbKTEhhp9D8P4uDLSLdBDUfvHqLEoym1HGapKedux4EXYKoojEEi5Z5VYnguayd7NUSY52ArFQLg1t28nxjbYD6jK6h2P73ztuGp6PNWpzmoifULoJsNnWwMprEuDB5jpn2BUrdg46NEEg3gVzo92epMz4Y1owPvSb4TTwbsWENWLqqz83tA949QUJkfULEHvNQdmFkLYcPL8xazrcf1LRRd">>
      ])

    for block <- blocks do
      {:ok, deserialized_block} = Aecore.Chain.Block.rlp_decode(Aeutil.Bits.decode58(block))

      assert :ok == Chain.add_block(deserialized_block),
             "block #{deserialized_block.header.height} #{inspect(Chain.add_block(deserialized_block))}"
    end
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

  defp assert_signed_txs_equal(our, epoch_rlp) do
    {:ok, epoch_tx_decoded} = SignedTx.rlp_decode(epoch_rlp)
    assert our == epoch_tx_decoded
    assert SignedTx.rlp_encode(our) == epoch_rlp
    assert SignedTx.validate(our) == :ok
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
