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
             "block #{deserialized_block.header.height}"
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
