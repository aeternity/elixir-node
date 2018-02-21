defmodule AecoreValidationTest do
  @moduledoc """
  Unit tests for the BlockValidation module
  """

  use ExUnit.Case
  doctest Aecore.Chain.BlockValidation

  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner

  @tag :validation
  test "validate new block" do
    prev_block = Chain.top_block()
    prev_chain_state = Chain.chain_state()
    Miner.mine_sync_block_to_chain()
    new_block = Chain.top_block

    assert new_block.header.prev_hash == BlockValidation.block_header_hash(prev_block.header)

    blocks_for_difficulty_calculation = [new_block, prev_block]
    _ = BlockValidation.calculate_and_validate_block!(
      new_block, prev_block, prev_chain_state, blocks_for_difficulty_calculation)
    wrong_height_block = %Block{new_block | header: %Header{new_block.header | height: 3}}
    assert {:error, "Incorrect height"} == catch_throw(
      BlockValidation.calculate_and_validate_block!(
        wrong_height_block, prev_block, prev_chain_state,
        blocks_for_difficulty_calculation))
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
