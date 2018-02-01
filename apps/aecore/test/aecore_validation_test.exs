defmodule AecoreValidationTest do
  @moduledoc """
  Unit tests for the BlockValidation module
  """

  use ExUnit.Case, async: false, seed: 0
  doctest Aecore.Chain.BlockValidation

  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Wallet.Worker, as: Wallet

  setup ctx do
    [
      wallet_path: File.cwd!
      |> Path.join("test/aewallet/")
      |> Path.join("wallet--2018-1-10-10-49-58"),
      wallet_pass: "1234",
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
    new_block =
      %Block{header: %Header{chain_state_hash: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0>>,
                             difficulty_target: 0,
                             height: 1,
                             nonce: 248_312_405,
                             pow_evidence: [383_234, 616_365, 623_137, 633_764,
                                            31_313_631, 31_326_664, 31_346_130,
                                            31_346_561, 31_373_638, 31_646_332,
                                            32_306_533, 32_313_362, 32_323_637,
                                            32_353_630, 32_363_064, 32_366_432,
                                            32_383_636, 32_386_561, 32_653_839,
                                            32_663_066, 33_356_265, 33_396_261,
                                            33_613_630, 33_616_333, 34_333_337,
                                            34_333_662, 34_393_965, 34_626_164,
                                            35_306_265, 35_333_837, 35_336_639,
                                            35_386_633, 35_393_931, 36_313_261,
                                            36_323_663, 37_313_335, 37_323_632,
                                            37_616_562, 37_616_634, 37_626_535,
                                            37_653_934, 37_656_233],
                             prev_hash: <<5, 106, 166, 218, 144, 176, 219, 99,
                             63, 101, 99, 156, 27, 61, 128, 219, 23, 42, 195,
                             177, 173, 135, 126, 228, 52, 17, 142, 35, 9, 218,
                             87, 3>>,
                             timestamp: 5000,
                             txs_hash: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0>>,
                             version: 1},
             txs: []}
    prev_block = %Block{header: %Header{difficulty_target: 0,
      height: 0, nonce: 1114,
      prev_hash: <<0::256>>,
      chain_state_hash: <<0::256>>,
      timestamp: 4000,
      pow_evidence: nil,
      txs_hash: <<0::256>>,
      version: 1},
      txs: []}
    blocks_for_difficulty_calculation = [new_block, prev_block]
    _ = BlockValidation.calculate_and_validate_block!(
      new_block, prev_block, %{}, blocks_for_difficulty_calculation)
    wrong_height_block = %Block{new_block | header: %Header{new_block.header | height: 2}}
    assert {:error, "Incorrect height"} == catch_throw( 
      BlockValidation.calculate_and_validate_block!(
        wrong_height_block, prev_block, %{}, 
        blocks_for_difficulty_calculation))
  end

  test "validate transactions in a block", ctx do
    from_acc = Wallet.get_public_key(ctx.wallet_pass)
    {:ok, tx1} = TxData.create(from_acc, ctx.to_acc, 5,
                              Map.get(Chain.chain_state,
                                ctx.to_acc, %{nonce: 0}).nonce + 1, 1, ctx.lock_time_block)
    {:ok, tx2} = TxData.create(from_acc, ctx.to_acc, 10,
                              Map.get(Chain.chain_state,
                                ctx.to_acc, %{nonce: 0}).nonce + 1, 1, ctx.lock_time_block)

    priv_key = Wallet.get_private_key(ctx.wallet_pass)
    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)
    {:ok, signed_tx2} = SignedTx.sign_tx(tx2, priv_key)

    block = %{Block.genesis_block | txs: [signed_tx1, signed_tx2]}
    assert block |> BlockValidation.validate_block_transactions
                 |> Enum.all? == true
  end
end
