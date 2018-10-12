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

  @tag :channels
  @tag :compatibility
  test "Blocks compatibility (create, transfer, partial transfer, solo with old, slash, settle)" do
    blocks =
      Enum.reverse(
      [
        <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutq13ykgN4t2fDuioyo2yU7Shxifx3audXKTyBYe8obxq9t4mnDKSrcQbre4FLSiJFDHX3rr9YpM2fmEmaomJNwGgtDUfLPruNaKxCyDHk55jjQYkBSjunu8oppEHsCg7m3cienHjBERuAMBeKJeycLkRN2kEoD7JTKdXLDau5mpQisEGvZnA3WZByEQdxQTznMV7i29PnqU9WWPSvFzGUwNm4SiefDVk5Fx95mBy2it1NgVKDv8PZTRBegBLUPDSv7LVNMMszdDUoJTzejECpVvbqtsZBoorLUbUcPjujngyD2Drf5R3gEhLZvzQsWHwnwnZK5modFbvdvgxQFCdea9enhvxBwmNzCec68eeub3pRRKHjgehRRKTG7HMBxbKaNgryNUJxcn1Q5cytj9wCyaMZVgqMcbeac4JGSEN2mjYZaWZEeHUrrSXpCRCdW">>,
        <<"inpJFdLA8ptKzb3fPL26ovqwjX9niJio62CtzShRiohxDbGgSYTxsMteHAe2ZjGXMfzBtLEp1hedvNjDgDNfzjzE4wi2DN8crBqrE8Gx7nh2CH7Fu2KPz81FcNUuSaimHNryATpbfipRc2XRAgpMfeD5zCBwX2f9FBsyniW5PqFDbZkarUiQuds652kNMAD53TH2YijwDBpSuTt6JG8eePU2N4bjNevSPWDDdmJSfoBj6hHqZhVNtArH7P81jvFRB88EwwwWYaFGH5Mw5j5VfEqhbarjgHfxrPuS3qwiTvLwDtygthanZktx39ugJ1unLLEeDLRk4xDYgjLuJL52kLCDrgfm9BQF4t7yBDjd1pkwAfHuonGT5L3QgERro5zAoM77XvkUc87qWgNWTki8ZkDZcmcYEWkMJaAdVHTHPsWfQgrnu5rBj2nPqJwfJo5TM3UGPCxEvDAzvMYUrQv8J4BdXf6z3oXfM8vHDXTRrYYHhRvfge5bTQ2uKUm4DbMZgG8f37hVycjLybS39pT5p3mRQVorshaqhek2RjeAdfepVAv64Xjba79X2qjo2PtoXKp7uM7pV4TohYJcfXZf7QBY3UYaXH26yRuT7tfm7uNfrTLf6PGkCWE2qVWapfnHx7x6HoizvHnTUtuFbUDFJsJHYm5Af3XsjbXTEDoBugFZzCJ">>,
 <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutpG1BvhTB4g2r4BxrsEpj26bPhx3GgWHCJBFkM5y6SihSGzSoN194aDwJ5CTGMT7RE11hb42Y1VfUpdGEhQhbEdzkfsu2QzsuM2a92r1xfwCzMfpAGgrBGcYqsn7SFDeZZcz7VZTk16Fc81p3mLPxMMsqgCJ3b7vW3KeNJQT3Krc3UGw39NwpWBL3gwMah32uj4JHqCRjk78RE1nvxssSC28UcpsPoV1mJRme9gePcpp4LhBURtwsmhDUpSkqsbjN9kpD8QCMS9XtbGsym4WxwmS3Jd2Rw6GsbzHv55haemg2hV3AJttZmjSKPYxCifv1jn7zXTLhob2HcAdT2gxCb7QuZ3BM7SXaBmj8srgAeW3ibgYSQMHDu7ADQ24oSJy8JkZNnZmbSyoQzwXhmzNEbgyEMpjiekz4HfVcHEWBpVW8MjvthEfh77ujNW78Q">>,
 <<"6p7DY5FhRBdkMGJfKmNwYxBa6DDQAonc5TLj98Fpca6mFr2a6zbaLr9mtCcWYrBZQHvZSyVM8ihwTgiRytPcrrGdCyj1xqVPooRugfeFXMg8DhMfezmbC7zNLupBd4q28MCJC97auHBSz2A7i7o25UXRBcUysoNEb21af86S8DJVBFDMz9UeG84DrSmJSCYhdWJBAqcmazYFcunKZvWMQDUboEQMgwFhuTtuDVK5er4rZ4LWQ7gfuNnQUcxbor7aQ78VXZUpaKjqYWJ4ZD8wayTHLnBHaQ5dwmmwrtiEBCEbV6GvgUu6RAy4Z4MwiSCbLatA8BbZ2GjH9BGhvarFMPeFwQApq52mpaYgvRAjHd7WvFurqbetkziG2wCRZFfzXKyrkUDmA7w9TpXcQY6iSP2oHRPFKj5d5pS1hDemz83yCh1w89QAKQ6pSpZnTiFQoiN6MJomjw3utV65CSDZESjWvC5a2MGJNZQW3gFSmmT8ZUiuTp6fDJ5mdfgrGmyq4QNFNGm2Fsev3niKpC1ZKiVx9hP4pFxZTXqyFxad27hd2y1FE5BpHruxZPA6SjbtWmCHiLur2hnRLF2YdojpRLbmmGka5c2iy3F69KL6o8qDvDRNAGADiQZxTDNSxm7EGZwhvEQhbPHfEzbya2fQsm8WfaVC61q1aif9iYDLxAN4GYawa1QufhzDM2Yk6BaP6mhbkLLSSdknS3W24pAzwGtg39ceDU9Mzg3SRKDbWjKK5i8ge7HzQKRGx26E3hgRewmyyMA9JFy9dtPv4vxYEkRoxG5hLX86W5Sg5eZtxvNLqeBbrY64DaetDGnbonxfnMVkXJqwgCWoGenn1wSh93FgJaCjDsacDu378nkREuzY8dnVAi8sE2xiwFWRYAk2F14jmDdkMce3Hj9baiFxwWJvqkcZTpmA688HspvH5dyBfWCZ4WDr2JCPxdqBw3ihMdkGhQJpMaXQGAxr1VaoEUyHDbm3NAXs6tfUF1EvjhdMvk5xw7vs21MC2QEAvY9NatbjcnoBhQhNL35WKiEokk513NpxhydAxkuTvxCsgVKFV5s4bjkrcve9GxgCVEbR7GTVqQjbSEshLXN34oJ6KKtpWQpCzSLyBFJXJdx2mJGPFiHoj2ffh9SrD5HpppWa9vkKHQsiQi3MXtaBfhbmJgZK6wFoESoQbY1DGaBdpKbxSNNsRE7D9WU8X7HcrDYeyL6ViPfeuN3QtZoZiiV14R8VXrjmdanDi9JA2MM5PZg3oakDzYzSy84euBwz8SAxUkQhT7qyvTw9rFXngaZUupZ7aXc58gPSxW9NaDaCCSyMEqXzfEFtbenqNeBPdgJYpUeB1AMjYmd1YJA255g4GkLyenHpHPSYnZuiymT7xuQKHwYdjggAKcDc8WtiSeYcsKUu71s1sy9Zgr9f2MJRh55DhWnWPUByrhbNivnkx6hUqnb1ktfD3TpKUZLWiTpN8XKYpQcPr9RfYMWzGHyeKJnuBwfx8ZBosP24vQTVF87fiZCz4pcSnx">>,
 <<"SevSdwYZQm8xMhym7zb7nFMdejVAPnQ8UxXVQcyaSFDtHxyhHAmfqoptZCJpXnZAQ33MbLbhM75Z9LmsXhdywtbshzCrBEoeZU31uAS3p4pb8rN8ZYZSLQmQgJDedafFCaxSc3iMs3NUhXT2ZLc8MoL5jztHWTQxgU2Xa8tsAEf4xTWaNyMPQwrRKWVxHQtzrDSQEwvuJBXYY9kjoPXanAjmiy7YXwEqF38fz2zrcf8MYd2s9XZbNVnae86yiYfibnBQN8mDtibg4tZQuvAirvY2LGuuqtQvVmG8ozmkscqyTTc3ZARo8pMDKrWNmBvJRTZDvtBUbqpXxZ9DNS6q1FwXGEwmBepqEUnZux7WhPNET71HtJaQMTC2Znb217kXJNzG7uJyDa5Vb3SYGYoQay89cfuYWCLeA1DoFhMdNAKk6cEFmQMZS66DAAzeCH34KMWNuQXDpug6is8WEnqZtQsENvhRRMmLhdh6zMAGiDXRW6bdqhVV6xbcxAHS9Fa3Xyce2Ssa9zwQKDar6C8zrYLPqoFbUiZ77WZDXpG2u5N8mJMoQVZ6oCr3SfZMxUezrXpK3pvubpmf1Syj9LJvpNJypsBJs8CjAW95jd9HyVn9hjtcq9mN5Phg6V6DVMpwVmwZ9pkwJo4xoXubaVJ3SaSrUanSNWEnR9u3nHmcNNH7zgHaBRKLqEZhKXPcT5PJ1Nmg3fg7LQEXhAZzhkJrba1FM5GpEFiAuJ35pK9395XumHMuQ38SstyNQtSi52s2HcM2wRsdf4o1ZoMp9Qi3j8LBLA8dGaLDRfuL7cKN7u7o576yDy6YCTz92vVste6FHXt9UasKgGQbkWwcmWqZkSC7NYfv46Zrfpf4FPrZ1wNtHN8gpMrRPKWMxfBayx5gcQXg8ywD5JKCni3fBAS3S4Tr1QK2C2ms6h8oJ2HGyfj1VHedHDaij7kTaoceYHReGX8c2SyLFSUCXvYHrj9gya8jQJ1yrP6mgk4boTbMbN1E8LSqNgfiMipk5VYHsCG2yu2HyoM5HkTBbv73NM4VRHyeeZRw5j8oqnz6Tes3ypvjc1brPX8jZTRbDiJVNiJDwW9NV5CnVAd1k1XxWsfFy47f7enuYSJ4vXdWVXdk1VCbh43CEUZDu86CzGskfh6XLk2thkY6UBMZ3nikyNPCnmVoZJFm44dCVgcy4SQCViKnTAs3ehSNTdSNkCtrcVcE21cDCojYJa2ojnzftvYAe4u6knwEjNtQw2Ud2i9fS9Ymocppjqzy1SjzDAoVi3gd2JKHw41eEv9VyqQMkWkFfpRjdKDwbExoX3QnBb1p1hZsXbS6KwsDby3DSEYhA265PvgBn3UimPJ11JmNUZunr5x4qECacPtgWPegqqbj9tD1GmLPJ6ac2G7zaTXoND79hDebMWe7poR8v67D8ugwJfC8j7nMu7QXn2of5Y9ae6HwTZkUpwq7vXw8wGCsFz6aMC3ciGGmPSgYcjUiiYitXxM7qWbE85rCApi2ijduN5CBjWeASNvcszE">>,
 <<"YeAhHiW4th91kLueniWv28xVikaSXbux2iqcCLrUfZW9DgV5QT9cFgwBvPHJdr3dYTBqoGPzECG3j8vkJXfhWVvWYRRCjadTBkhVBGunctGi6RAUeU9zuc9MvPUpQZTdZofLGtDztNVWnb2aun68iNn4NdCwiNJYoxsuYsjsjAmkzrLzkisZvjDvNYBfrNMhwGfZkN3tQgKARVu4wzb1ManSJiKC9Uz4T3vKe1tyQZz45s38L5B381iHTp3AckGw1nT52ZDj2WN3Wk53pQe8jAhAh1ZedTg4Gm7AJzK8srHiY45zxxrVtifjfDMfJHKWpEHZXaGCDW698MjemQcsYG4tgQcLybE7XLuUgE9FhXWJAstNTvpoqBQs6gXvdDcd2oweyrDLeRg32YmXvnuypDxNii92EcpCXqLvseG6QNMUEC4d7HxeDhH2p4yFUfKSBtxbK6Cw8keCZRTSULtCqPXup4EJuBtBg1HVXJpL61DG313rvUGqFN21UdN1fHJ4Nb7mUhKUqTwzDFfUdWCrvZqJNJF82LTS6vGeuXvXYNvwin8djMLQQgufpuVi41j4KNNvcaJgdp3pGcHu2mFB1fgmZ6MPcmEkD9618QVueTJkyYTqtUnTf3duDkgHTTSMygK2ysyGfpVhK1Ca4KkM1RZNAFfPMvfzzh8yEm4SJEQ5m3fs8fqa4qy2VLvuC7pC7L5gVTptwheg2UQ2tSZ7d777Rk5PphD41SagdzZco61abXWCUyHFzhTX8DNyVSzqneHexPfjE1oGy8DAgcZoroQ68ucMfryiUjSpY8XRLDsa5xbecvkwWCzFj">>,
 <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutmvZsEicVYD8PnpaED24HRqBbYHPTGD6iwWad9ZJT1v772wfHJoJsJQZagR6MnDAGEhK9fewAtK1YWR7aMHvxWqD92mCzv33mjKiafs4qS8c1gb9Eq5wRzsKkyVq584RqdCYaiiqv395UeUDZTXAD2r8jgxsY5H3hRGL2a8xLpRxm19ViNM5e3HecFMFPqEV4nysy2jJgFajKSE9rEGuHHYCJrUF3xN2zKjks6re5jDSkDNLX1g4XMQAoZbqf1C6Sx6x1NQsrgXAHSwhrwPXLLgwWyA8cpmTu1WvJ7VW9412gzpJcfDpWmbdKJkbKYVPt4BCo3EgxqPiBAxWTjnxbgTPbu71gYXm3oK4V35piUjhrN4MemozqeRcyrBoYiANz4wuxzTkk9jNjaAFHBU1Q2MQ5XRwt5YS59MXnJJtWLU3xf8n5M6ssHR8WmCXaV">>,
 <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutmmPFNP9jAW68khSv1dyMf1Ucan8Ngc62Da85CVrY7sE8h8bMNkHf2ckMTzeFzueEf6kaB3CMsHRdsW2pdssKkHLCsnBnQWEXgbz7Rqy4vjCnBUM5cvb5EBVRvqZTWwhA1koLkEXMyG2NJBqJWG9EBJSjWAg417m7VieowbBdjQrvqn1hRRmxN6WqZ2S8mPvRBc9B4YspZYBchQc6vjLqgBw2bx4SdyayFGX6CpcFvxHL6zqPCKRumWdku52tbWogBL4x6fm6Wx6n3H49nFZNga5MHzb1WjWEYN7P9WGCeXu1ub4xesk2Z4uSgnnR8vNmDfGTeRGMKojvViLBNyxjfDBK7ad89C8sdqmcDVe5pJF9cFcSGDpb1SbKtSWNLpeAYN3zHfeHviT98tK5VRMdRKooHok2C3JctQb3MbKS6sXbGRdGgRNvhriMEzk29">>,
 <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutktvsDYjpv3SrrY91VBP1Q66amGgkac9D3Lx29xNYQWrZJsc8HLjNSJKXPANqvwWs5FF8so3LeA8cwMeXrsWV8frw7ncbcuSxLwRcSkX3uzusmSvcfWSU7uPZqexpBV2j7Jt76xsUu3yySwsQvRmSRVqhGyFg592mvjFiv5KsvQvg9yA8sY6obqPEs6FLB86tEV3ouEu4sUsXU7YGUYTgSr7zJ7meGTEDevR44esEpsnViDFeyjC1XFEHsu3uBjbSbkGhBSADpm2QMf3Fh7LpU2L7DQURD4U9kRcN7QAwhxFcqJjJhJWi4B7Pr38pDVj5NasqUvtA78yNtRmfZdY2oxwTpxmgKBhNSxfxxTJTxaAYhFiD8bpFSUXfaitb4utFKC3dkEn7vnqwtFuiCFPS2VvkHwx8GJZ6WWDNyFBZrr49f1FWQMjvsiubHnzgZ">>,
 <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutkSsW5q52VHWaMyRE5VoxuobCC5WaNMXxfGh6MBcMpGnWUcBVHHaQyH6Sx4NTGDTgnursPmR8YiwxbELMRFbo2U1U29t1adUBCwwUwaBE6pr9VPmvQVX89PwmxBohrbK4ZtFfpJ21r6uxBCFbkYh6nyGSYBt9CfcSNz83t1RUbBCadbPSFru4hmyfn7u8oGjidethWuveVW6f9nZW32ZKM1gTJsEosoALFLNQHKYcyNBFSMdJS8xWDwGi8f1qcZzf22xwFDjJAKkpjK43yVgG25QFPSUsJ5pckCa2JVZpvznSuj8hq3F2CmJdikC77d1XoxyUKuXUF8BdPAZe7jtWzKaXh7eeLphjRsLks9LJiEuRf3Nak6R84idAujTDgoZERnyXy3yvSxwfMqrvxVL8zfpRUNvvFkzrfwK84MGkpJU1SdZhM9CgEz7EKNKo4">>,
 <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutk7bykmvUwaZKGmzvgMha1Eq9eaBMyxcoFshkJFkaQWWKG2qoEUn6Xpj1v8ZDNXenuCKe1RWvQEDbGCff6oMu7HCr2xbZm5TvNKWv7VFTxDUe4uygizDmteRntu7TRWz8gfM7podVWvPc4u2unoFFofiLqEijz85DXcjQM8BNv1D6LNwKcEvD9fsFerHmDsHMondVowMBtqa65hJBy3ydKesNjDW2ZiVBoeUJer5uV5enS6G1jN5uDZdWgtkyNkmRADLkRiSjmK6wnbrfw2LTga3n7dfschFMzivKXFo4w9n4xqMQcoqcCjNCFuSkrVEcFrPjTqQo5aMYSFo5YZcGLYLLBYPgY1CZ133rFDMZeuUxTVF1gN51CNMdFR6BWu6LMo9RsSm4m3Gu4L9mhPGafZAwSm7trBD3HtZ78TvXChvYgVBEcumNvzkDpbaGM">>,
 <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutjannPRC5BGarX47K5a1U1YUTTUv5oVPnjhw7nWeWkgkhUXcrXq9KZ6njcpVUPhYpXpFwbpUv3Zrcbo7AGKtdvb9vwhVRmuZgrQ6k7VebFH36YWtgLFiEKmMsUy4WJcyfjytEnfPThEZ9jQytpLZTqMsShy1NztttC1Y6ivhdNTYuz5xSzKw8ViRscMWCnik4Mes7vcEqcMTcYBWXCGvjTYNF5mNkbUMJ9ZM9DcboZfNih5hQr7Pp4bsKVhceSkjNE7RWNeyYLLcSF2NoonUuMt8nC1Fg5jqdyRy5AipMEpGspzatttZotZgvuQHmNr1o2C9zZPDCPNBbfVTQWbcsbwpT6qC3Vh8XSPiDjmf7ZcqPar988pScvfgPYV5F2to46g4EXBSUvR74RsW3QYGfSf73aHvQCbFoLijepNzQfnsKh6XdUH8hh6uTNyGac">>,
 <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutiwMEigt7XboNNQmHzjHq2V1ksxjLAWDVFfyZdwwcKVbEZzjrJnWdfmgpH2U9xn7Y3FkhBbrXr1THzgAKG4WEy97TkTb1Atgzom2zVs4YiwCihfHpnTMBGE1Vk49gtU8ciWSYGptQH6A3oBh3ooSmv8jqEP7HpANp9yLRD5Ms8zKEVqk9o8JVkoNwNGSgw715rWQ54TdgpV4QToy9qYFrkLFpBuNtRR6f7q4bUJWc31ByxsQnUmpZbttHNGhmZH6wv9rF5yR5v1FKhvbfKqYxkPdYSf3kHyrxrsBcKqzEgszmW5qU9XZiEz1j4uTke7mXDJKX65FyDj7tHR6Sd1efVgySqJN42KyJvYamZQMT4LGTBxHEeb1oJbCUFZSLdiH7AdiWt41pAi464DaorSdMqv7FresxF8iJM4EJiwaeqUomPJh2uat9gt3xEUfp5">>,
 <<"CoaCsVSmrGnEoTzjTqmtMbmqJRVsLkutikLVdAqrqvqaquwLnGqTNoU8jy8ndyxwxsVTr2JJsRgFctDoC6Ccxfnq8fsCL2hsnWB4xshaBquFUb1WjhibGjwEryoAHyFPLjtgPuQTLXWscw6aJTwdHuPYF7ihTV7w23D7vRwxH9rA1xWYwCzoZhjhcDznEz3tJ6z2sjnPkD8fcbzg8MaKURKxWXbWfgV9SPF9As4ZDocjBiiXt1B3EYTCbXbd1nGARFUuLHaS3sTZMQS75fZXJZKVGGinqgXZdC7CH2FEbwtR1eNEJeqYpCLmp9tzo3Bvizz3CjXy7stRF9BQDnLaFDipiRK77shre5J2vDcnnsoDNbCb7gCErtEkXHPApz7kfHN6KByPsJcXcJhWJ9RuJrG91osudEPkWEqVYm3X1fT8sj8BLMXVWFkGMvvShVRZvgufk1Drr9yTDfQyzuMNrHSDwbzDh">>
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
    {:ok, epoch_tx_decoded} = ChannelOffChainTx.rlp_decode_signed(epoch_rlp)
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
