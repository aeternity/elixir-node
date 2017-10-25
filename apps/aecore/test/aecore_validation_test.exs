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

  test "validate new block" do
    new_block =
      %Block{header: %Header{chain_state_hash: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                             0, 0, 0, 0, 0, 0>>,
                             difficulty_target: 0,
                             height: 1,
                             nonce: 248312465,
                             pow_evidence: [120297, 2773345, 2888004,
                                            3205628, 3892057, 4641559,
                                            4965070, 6073954, 6646758,
                                            6795379, 7122989, 7652486,
                                            7678291, 8877562, 9488544,
                                            9681443, 10062039, 10068406,
                                            10326714, 13492685, 14935090,
                                            15766625, 16049365, 17080853,
                                            19115090, 20932979, 21264542,
                                            21805321, 22257518, 24305695,
                                            25103635, 25451917, 27447766,
                                            27848723, 28668621, 28927953,
                                            29987064, 30191762, 30739459,
                                            31412879, 31503699, 33202971],
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
    {:ok, tx1} = Keys.sign_tx(elem(Keys.pubkey(), 1), 5)
    {:ok, tx2} = Keys.sign_tx(elem(Keys.pubkey(), 1), 10)

    block = %{Block.genesis_block | txs: [tx1, tx2]}
    assert block |> BlockValidation.validate_block_transactions
                 |> Enum.all? == true
  end

end
