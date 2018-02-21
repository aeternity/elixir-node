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

  @tag :validation
  test "validate block header height" do
    new_block = get_new_block()
    prev_block = get_prev_block()
    
    blocks_for_difficulty_calculation = [new_block, prev_block]
   # _ = BlockValidation.calculate_and_validate_block!(new_block, prev_block, get_chain_state(), blocks_for_difficulty_calculation)
    wrong_height_block = %Block{new_block | header: %Header{new_block.header | height: 300}}
    assert {:error, "Incorrect height"} == catch_throw(BlockValidation.calculate_and_validate_block!(
      wrong_height_block, prev_block, get_chain_state(), blocks_for_difficulty_calculation))
  end

  @tag :validation
  test "validate block header timestamp" do
    new_block = get_new_block()
    prev_block = get_prev_block()

    blocks_for_difficulty_calculation = [new_block, prev_block]
    #_ = BlockValidation.calculate_and_validate_block!(new_block, prev_block, get_chain_state(), blocks_for_difficulty_calculation)
    wrong_timestamp_block = %Block{new_block | header: %Header{new_block.header | timestamp: 10}}
    assert {:error,"Invalid header timestamp"} == catch_throw(BlockValidation.calculate_and_validate_block!(
      wrong_timestamp_block, prev_block, get_chain_state(), blocks_for_difficulty_calculation))
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

  def get_new_block() do
    from_pubkey = elem(Aecore.Keys.Worker.pubkey(), 1)
    to_account = <<4, 94, 96, 161, 182, 76, 153, 22, 179, 136, 60, 87, 225, 135, 253, 179, 80, 40, 80, 149, 21, 26, 253, 48, 139, 155, 200, 45, 150, 183, 61, 46, 151, 42, 245, 199, 168, 60, 121, 39, 180, 82, 162, 173, 86, 194, 180, 54, 116, 190, 199, 155, 97, 222, 85, 83, 147, 172, 10, 85, 112, 29, 54, 0, 78>>
    {:ok, tx1} = Aecore.Keys.Worker.sign_tx(to_account, 100, Map.get(Aecore.Chain.Worker.chain_state, from_pubkey, %{nonce: 0}).nonce + 1, 10)
    Aecore.Txs.Pool.Worker.add_transaction(tx1)
    {:ok,new_block} = Aecore.Miner.Worker.mine_sync_block(Aecore.Miner.Worker.candidate)
    new_block
  end

  def get_prev_block() do
    Aecore.Chain.Worker.top_block()
  end

  def get_chain_state() do
    Aecore.Chain.Worker.chain_state()
  end
end
