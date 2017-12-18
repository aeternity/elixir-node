defmodule AecoreValidationTest do
  @moduledoc """
  Unit tests for the BlockValidation module
  """

  use ExUnit.Case
  doctest Aecore.Chain.BlockValidation

  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain

  test "validate new block" do
    new_block =
      %Block{header: %Header{chain_state_hash: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0>>,
                             difficulty_target: 0,
                             height: 1,
                             nonce: 248_312_374,
                             pow_evidence: [8_081, 47_553, 48_385, 49_312, 51_555,
                                            64_159, 71_996, 78_044, 90_415, 102_863,
                                            113_010, 124_096, 126_548, 148_419,
                                            164_411, 166_884, 181_371, 195_117,
                                            195_929, 204_532, 214_522, 238_027,
                                            239_685, 245_406, 271_421, 277_983,
                                            289_169, 329_736, 330_930, 334_253,
                                            339_312, 342_060, 384_756, 393_044,
                                            410_582, 414_490, 429_226, 429_839,
                                            430_507, 482_481, 493_187, 510_666],
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
                              Map.get(Chain.chain_state,
                                      to_account, %{nonce: 0}).nonce + 1, 1,
                              Chain.top_block().header.height +
                                Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1)
    {:ok, tx2} = Keys.sign_tx(to_account, 10,
                              Map.get(Chain.chain_state,
                                      to_account, %{nonce: 0}).nonce + 1, 1,
                              Chain.top_block().header.height +
                                Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1)

    block = %{Block.genesis_block | txs: [tx1, tx2]}
    assert block |> BlockValidation.validate_block_transactions
                 |> Enum.all? == true
  end

end
