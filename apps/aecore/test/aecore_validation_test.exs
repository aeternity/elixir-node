defmodule AecoreValidationTest do
  @moduledoc """
  Unit tests for the BlockValidation module
  """

  use ExUnit.Case
  doctest Aecore.Utils.Blockchain.BlockValidation

  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain

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
    assert BlockValidation.validate_block!(new_block, prev_block, %{},
                                    blocks_for_difficulty_calculation) == :ok
  end

  test "validate transactions in a block" do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx1} = Keys.sign_tx(to_account, 5,
                              Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 1)
    {:ok, tx2} = Keys.sign_tx(to_account, 10,
                              Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 1)

    block = %{Block.genesis_block | txs: [tx1, tx2]}
    assert block |> BlockValidation.validate_block_transactions
                 |> Enum.all? == true
  end

end
