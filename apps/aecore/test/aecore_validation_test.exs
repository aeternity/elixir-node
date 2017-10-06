defmodule AecoreValidationTest do
  @moduledoc """
  Unit tests for the BlockValidation module
  """

  use ExUnit.Case
  doctest Aecore.Utils.Blockchain.BlockValidation

  alias Aecore.Utils.Blockchain.BlockValidation, as: BlockValidation
  alias Aecore.Structures.Block, as: Block
  alias Aecore.Structures.Header, as: Header

  test "validate new block" do
    new_block = %Block{header: %Header
      {difficulty_target: 0,
      height: 1, nonce: 1016,
      prev_hash: <<0, 72, 231, 138, 54, 240, 249, 116, 135, 48, 177, 11, 151, 240, 85, 155, 175,
  148, 110, 27, 59, 69, 75, 208, 92, 121, 228, 14, 249, 26, 21, 155>>,
      timestamp: 5000,
      txs_hash: <<0::256>>,
      version: 1},
      txs: []}
    prev_block = %Block{header: %Header{difficulty_target: 0,
      height: 0, nonce: 1114,
      prev_hash: <<0::256>>,
      timestamp: 4000,
      txs_hash: <<0::256>>,
      version: 1},
      txs: []}
    assert BlockValidation.validate_block!(new_block,prev_block) == :ok
  end

  test "validate transactions in a block" do
    txs = [Aecore.Txs.Tx.create(Aecore.Keys.Worker.pubkey(), 5),
           Aecore.Txs.Tx.create(Aecore.Keys.Worker.pubkey(), 10)]
    block = Block.create()
    block = %{block | txs: txs}
    assert block |> BlockValidation.validate_block_transactions
                 |> Enum.all? == true
  end

end
