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

  test "validate new block" do
    new_block =
      %Block{header: %Header{chain_state_hash: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0>>,
                             difficulty_target: 0,
                             height: 1,
                             nonce: 248312374,
                             pow_evidence: [8081, 47553, 48385, 49312, 51555,
                                            64159, 71996, 78044, 90415, 102863,
                                            113010, 124096, 126548, 148419,
                                            164411, 166884, 181371, 195117,
                                            195929, 204532, 214522, 238027,
                                            239685, 245406, 271421, 277983,
                                            289169, 329736, 330930, 334253,
                                            339312, 342060, 384756, 393044,
                                            410582, 414490, 429226, 429839,
                                            430507, 482481, 493187, 510666],
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
    assert BlockValidation.validate_block!(new_block,prev_block, %{}) == :ok
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
