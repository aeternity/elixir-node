defmodule AecoreValidationTest do
  @moduledoc """
  Unit tests for the BlockValidation module
  """

  use ExUnit.Case
  doctest Aecore.Chain.BlockValidation

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.BlockValidation
  alias Aecore.Chain.Difficulty
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Structures.Account

  setup_all do
    Code.require_file("test_utils.ex", "./test")
    path = Application.get_env(:aecore, :persistence)[:path]

    if File.exists?(path) do
      File.rm_rf(path)
    end

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)
  end

  setup ctx do
    Miner.mine_sync_block_to_chain()

    [
      receiver: Wallet.get_public_key("M/0")
    ]
  end

  @tag :validation
  test "validate block header height", ctx do
    new_block = get_new_block(ctx.receiver)
    prev_block = get_prev_block()

    top_block = Chain.top_block()
    top_block_hash = BlockValidation.block_header_hash(top_block.header)

    blocks_for_difficulty_calculation =
      Chain.get_blocks(top_block_hash, Difficulty.get_number_of_blocks())

    _ =
      _ =
      BlockValidation.calculate_and_validate_block!(
        new_block,
        prev_block,
        get_chain_state(),
        blocks_for_difficulty_calculation
      )

    incorrect_pow_block = %Block{new_block | header: %Header{new_block.header | height: 10}}

    assert {:error, "Header hash doesnt meet the target"} ==
             catch_throw(
               BlockValidation.calculate_and_validate_block!(
                 incorrect_pow_block,
                 prev_block,
                 get_chain_state(),
                 blocks_for_difficulty_calculation
               )
             )
  end

  @tag :validation
  @timeout 10_000_000
  test "validate block header time", ctx do
    Miner.mine_sync_block_to_chain()

    new_block = get_new_block(ctx.receiver)
    prev_block = get_prev_block()

    top_block = Chain.top_block()
    top_block_hash = BlockValidation.block_header_hash(top_block.header)

    blocks_for_difficulty_calculation =
      Chain.get_blocks(top_block_hash, Difficulty.get_number_of_blocks())

    _ =
      BlockValidation.calculate_and_validate_block!(
        new_block,
        prev_block,
        get_chain_state(),
        blocks_for_difficulty_calculation
      )

    wrong_time_block = %Block{
      new_block
      | header: %Header{
          new_block.header
          | time:
              System.system_time(:milliseconds) + System.system_time(:milliseconds) +
                30 * 60 * 1000
        }
    }

    assert {:error, "Invalid header time"} ==
             catch_throw(
               BlockValidation.calculate_and_validate_block!(
                 wrong_time_block,
                 prev_block,
                 get_chain_state(),
                 blocks_for_difficulty_calculation
               )
             )
  end

  @timeout 10_000
  test "validate transactions in a block", ctx do
    sender = Wallet.get_public_key()
    amount = 5
    fee = 1

    nonce = Account.nonce(TestUtils.get_accounts_chainstate(), sender) + 1
    payload1 = %{receiver: ctx.receiver, amount: amount}
    tx1 = DataTx.init(SpendTx, payload1, sender, fee, nonce + 1)

    payload2 = %{receiver: ctx.receiver, amount: amount + 5}
    tx2 = DataTx.init(SpendTx, payload2, sender, fee, nonce + 2)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)
    {:ok, signed_tx2} = SignedTx.sign_tx(tx2, priv_key)

    block = %{Block.genesis_block() | txs: [signed_tx1, signed_tx2]}

    assert block
           |> BlockValidation.validate_block_transactions()
           |> Enum.all?() == true
  end

  def get_new_block(receiver) do
    sender = Wallet.get_public_key()
    amount = 100
    nonce = Account.nonce(TestUtils.get_accounts_chainstate(), sender) + 1
    fee = 10

    payload = %{receiver: receiver, amount: amount}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, nonce)
    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    Aecore.Txs.Pool.Worker.add_transaction(signed_tx)
    {:ok, new_block} = Aecore.Miner.Worker.mine_sync_block(Miner.candidate())
    new_block
  end

  def get_prev_block do
    Chain.top_block()
  end

  def get_chain_state do
    Chain.chain_state()
  end
end
