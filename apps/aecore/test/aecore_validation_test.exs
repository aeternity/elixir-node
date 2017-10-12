defmodule AecoreValidationTest do
  @moduledoc """
  Unit tests for the BlockValidation module
  """

  use ExUnit.Case
  doctest Aecore.Utils.Blockchain.BlockValidation

  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aecore.Keys.Worker, as: Keys

  test "validate new block" do
    new_block = %Block{header: %Header
      {difficulty_target: 0,
      height: 1, nonce: 1016,
      prev_hash:
      <<145, 211, 229, 74, 60, 194, 178, 139, 216, 166, 140, 193, 171, 193, 39, 182,
      240, 12, 216, 218, 93, 219, 93, 31, 73, 138, 53, 89, 186, 200, 242, 100>>,
      chain_state_hash: <<0::256>>,
      timestamp: 5000,
      txs_hash: <<0::256>>,
      version: 1},
      txs: []}
    prev_block = %Block{header: %Header{difficulty_target: 0,
      height: 0, nonce: 1114,
      prev_hash: <<0::256>>,
      chain_state_hash: <<0::256>>,
      timestamp: 4000,
      txs_hash: <<0::256>>,
      version: 1},
      txs: []}
    assert BlockValidation.validate_block!(new_block,prev_block, %{}) == :ok
  end

  test "validate transactions in a block" do
    txs = [SignedTx.create(Keys.pubkey(), 5),
           SignedTx.create(Keys.pubkey(), 10)]
    block = %{Block.genesis_block | txs: txs}
    assert block |> BlockValidation.validate_block_transactions
                 |> Enum.all? == true
  end

end
