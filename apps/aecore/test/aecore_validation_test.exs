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
    {:ok ,pubkey} = Aecore.Keys.Worker.pubkey()
    txs = [Aecore.Txs.Tx.create(pubkey, 5),
           Aecore.Txs.Tx.create(pubkey, 10)]
    block = Block.create()
    block = %{block | txs: txs}
    assert block
    |> BlockValidation.validate_block_transactions
    |> Enum.all? == true
  end

end
