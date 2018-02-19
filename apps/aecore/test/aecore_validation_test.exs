defmodule AecoreValidationTest do
  @moduledoc """
  Unit tests for the BlockValidation module
  """

  use ExUnit.Case, async: false, seed: 0
  doctest Aecore.Chain.BlockValidation

  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Wallet.Worker, as: Wallet

  setup ctx do
    [
      wallet_pass: Application.get_env(:aecore, :aewallet)[:pass],
      to_acc: <<4, 3, 85, 89, 175, 35, 38, 163, 5, 16, 147, 44, 147, 215, 20, 21, 141, 92,
      253, 96, 68, 201, 43, 224, 168, 79, 39, 135, 113, 36, 201, 236, 179, 76, 186,
      91, 130, 3, 145, 215, 221, 167, 128, 23, 63, 35, 140, 174, 35, 233, 188, 120,
      63, 63, 29, 61, 179, 181, 221, 195, 61, 207, 76, 135, 26>>,
      lock_time_block: Chain.top_block().header.height +
      Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1
    ]
  end

  @tag :validation
  test "validate new block" do
    new_block = get_new_block()
    prev_block = get_prev_block()

    blocks_for_difficulty_calculation = [new_block, prev_block]
    _ = BlockValidation.calculate_and_validate_block!(
      new_block, prev_block, get_chain_state(), blocks_for_difficulty_calculation)
    wrong_height_block = %Block{new_block | header: %Header{new_block.header | height: 3}}
    assert {:error, "Incorrect height"} == catch_throw(
      BlockValidation.calculate_and_validate_block!(
        wrong_height_block, prev_block, get_chain_state(),
        blocks_for_difficulty_calculation))
  end

  test "validate transactions in a block", ctx do
    from_acc = Wallet.get_public_key(ctx.wallet_pass)
    {:ok, tx1} = SpendTx.create(from_acc, ctx.to_acc, 5,
                              Map.get(Chain.chain_state,
                                ctx.to_acc, %{nonce: 0}).nonce + 1, 1, ctx.lock_time_block)
    {:ok, tx2} = SpendTx.create(from_acc, ctx.to_acc, 10,
                              Map.get(Chain.chain_state,
                                ctx.to_acc, %{nonce: 0}).nonce + 1, 1, ctx.lock_time_block)

    priv_key = Wallet.get_private_key(ctx.wallet_pass)
    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)
    {:ok, signed_tx2} = SignedTx.sign_tx(tx2, priv_key)

    block = %{Block.genesis_block | txs: [signed_tx1, signed_tx2]}
    assert block |> BlockValidation.validate_block_transactions
                 |> Enum.all? == true
  end

  def get_new_block() do
    %Block{header: %Header{chain_state_hash: <<100,
    126, 168, 5, 157, 180, 101, 231, 52, 4, 199, 197, 80, 234, 98, 146, 95,
    154, 120, 252, 235, 15, 11, 210, 185, 212, 233, 50, 179, 27, 64, 35>>,
    difficulty_target: 1, height: 2, nonce: 54,
    pow_evidence: [3964, 316334, 366465, 376566, 386164, 623237, 633065, 643432,
    643561, 653138, 653833, 31323331, 31323834, 31373436, 31383066, 31386335,
    31613935, 32313438, 32356432, 33303439, 33383035, 33386236, 33393063,
    33663337, 34326534, 34333833, 34613162, 34623533, 34663436, 35353130,
    35376262, 35656432, 36303437, 36306330, 36313862, 36323634, 36386134,
    36623130, 36626131, 37343836, 37353437, 37643235],
    prev_hash: <<55, 64, 192, 115, 139, 134, 169, 4, 34, 58, 167, 7, 162, 142,
    37, 211, 18, 226, 50, 221, 144, 34, 249, 79, 84, 219, 165, 63, 188, 186,
    213, 202>>, timestamp: 1518426070901,
    txs_hash: <<73, 160, 195, 51, 40, 152, 177, 68, 126, 28, 250, 214, 176, 20,
    202, 175, 222, 181, 108, 11, 106, 182, 80, 122, 179, 208, 233, 75, 222, 83,
    102, 160>>, version: 1},
    txs: [%SignedTx{data: %SpendTx{fee: 0,
    from_acc: nil, lock_time_block: 12, nonce: 0,
    to_acc: <<4, 189, 182, 95, 56, 124, 178, 175, 226, 223, 46, 184, 93, 2, 93,
     202, 223, 118, 74, 222, 92, 242, 192, 92, 157, 35, 13, 93, 231, 74, 52,
     96, 19, 203, 81, 87, 85, 42, 30, 111, 104, 8, 98, 177, 233, 236, 157,
     118, 30, 223, 11, 32, 118, 9, 122, 57, 7, 143, 127, 1, 103, 242, 116,
     234, 47>>, value: 100}, signature: nil}]}
  end

  def get_prev_block() do
    %Block{header: %Header{chain_state_hash: <<230,
    129, 113, 45, 47, 180, 171, 8, 15, 55, 74, 106, 150, 170, 190, 220, 32, 87,
    30, 102, 106, 67, 131, 247, 17, 56, 115, 147, 17, 115, 143, 196>>,
    difficulty_target: 1, height: 1, nonce: 20,
    pow_evidence: [323237, 333766, 346430, 363463, 366336, 383965, 653638,
    663034, 31313230, 31316539, 31326462, 31383531, 31636130, 32343435,
    32346663, 32363234, 32613339, 32626666, 32636335, 32656637, 32663432,
    33356639, 33363166, 33366138, 33393033, 33613465, 34316561, 34353064,
    35303264, 35356635, 35373439, 35613039, 35616266, 35663939, 36336334,
    36376631, 36396432, 36613239, 36613539, 36626364, 36643466, 37343266],
    prev_hash: <<188, 84, 93, 222, 212, 45, 228, 224, 165, 111, 167, 218, 25, 31,
    60, 159, 14, 163, 105, 206, 162, 32, 65, 127, 128, 188, 162, 75, 124, 8,
    229, 131>>, timestamp: 1518426067973,
    txs_hash: <<170, 58, 122, 219, 147, 41, 59, 140, 28, 127, 153, 68, 245, 18,
    205, 22, 147, 124, 157, 182, 123, 24, 41, 71, 132, 6, 162, 20, 227, 255,
    25, 25>>, version: 1},
    txs: [%SignedTx{data: %SpendTx{fee: 0,
    from_acc: nil, lock_time_block: 11, nonce: 0,
    to_acc: <<4, 189, 182, 95, 56, 124, 178, 175, 226, 223, 46, 184, 93, 2, 93,
     202, 223, 118, 74, 222, 92, 242, 192, 92, 157, 35, 13, 93, 231, 74, 52,
     96, 19, 203, 81, 87, 85, 42, 30, 111, 104, 8, 98, 177, 233, 236, 157,
     118, 30, 223, 11, 32, 118, 9, 122, 57, 7, 143, 127, 1, 103, 242, 116,
     234, 47>>, value: 100}, signature: nil}]}
  end

  def get_chain_state() do
    %{<<4, 189, 182, 95, 56, 124, 178, 175, 226, 223, 46, 184, 93, 2, 93, 202, 223,
    118, 74, 222, 92, 242, 192, 92, 157, 35, 13, 93, 231, 74, 52, 96, 19, 203,
    81, 87, 85, 42, 30, 111, 104, 8, 98, 177, 233, 236, 157, 118, 30, 223, 11,
    32, 118, 9, 122, 57, 7, 143, 127, 1, 103, 242, 116, 234, 47>> =>
    %{balance: 0, locked: [%{amount: 100, block: 11}], nonce: 0}}
  end
end
