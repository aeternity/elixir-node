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
      height: 1, nonce: 1000,
      prev_hash: <<56, 173, 88, 151, 61, 137, 95, 16, 18, 72, 5, 88, 244, 102, 38, 245, 206, 31,
  187, 170, 137, 15, 58, 93, 12, 100, 249, 224, 68, 145, 36, 253>>,
      timestamp: 5000,
      txs_hash: <<0::256>>,
      version: 1},
      txs: []}
    prev_block = %Block{header: %Header{difficulty_target: 0,
      height: 0, nonce: 1000,
      prev_hash: <<0::256>>,
      timestamp: 4000,
      txs_hash: <<0::256>>,
      version: 1},
      txs: []}
    assert BlockValidation.validate_block(new_block,prev_block) == :ok
  end

end
