defmodule AecoreValidationTest do
  @moduledoc """
  Unit tests for the BlockValidation module
  """

  use ExUnit.Case
  doctest Aecore.Chain.BlockValidation

  alias Aecore.Chain.BlockValidation
  alias Aecore.Chain.{Block, Header, Genesis}
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Keys
  alias Aecore.Account.Account
  alias Aecore.Governance.GovernanceConstants

  setup_all do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()

    path = Application.get_env(:aecore, :persistence)[:path]

    if File.exists?(path) do
      File.rm_rf(path)
    end

    tests_pow = Application.get_env(:aecore, :pow_module)
    Application.put_env(:aecore, :pow_module, Aecore.Pow.Cuckoo)

    on_exit(fn ->
      TestUtils.clean_blockchain()
      Application.put_env(:aecore, :pow_module, tests_pow)
    end)
  end

  setup _ctx do
    Miner.mine_sync_block_to_chain()
    %{public: receiver} = :enacl.sign_keypair()

    [
      receiver: receiver
    ]
  end

  @tag :validation
  test "validate block header height", ctx do
    new_block = get_new_block(ctx.receiver)
    prev_block = get_prev_block()

    top_block = Chain.top_block()
    top_block_hash = Header.hash(top_block.header)

    blocks_for_target_calculation =
      Chain.get_blocks(
        top_block_hash,
        GovernanceConstants.number_of_blocks_for_target_recalculation()
      )

    _ =
      BlockValidation.calculate_and_validate_block(
        new_block,
        prev_block,
        get_chain_state(),
        blocks_for_target_calculation
      )

    incorrect_pow_block = %Block{new_block | header: %Header{new_block.header | height: 10}}

    assert {:error, "#{BlockValidation}: Header hash doesnt meet the target"} ==
             BlockValidation.calculate_and_validate_block(
               incorrect_pow_block,
               prev_block,
               get_chain_state(),
               blocks_for_target_calculation
             )
  end

  @tag :validation
  test "validate block header time", ctx do
    Miner.mine_sync_block_to_chain()

    new_block = get_new_block(ctx.receiver)
    prev_block = get_prev_block()

    top_block = Chain.top_block()
    top_block_hash = Header.hash(top_block.header)

    blocks_for_target_calculation =
      Chain.get_blocks(
        top_block_hash,
        GovernanceConstants.number_of_blocks_for_target_recalculation()
      )

    _ =
      BlockValidation.calculate_and_validate_block(
        new_block,
        prev_block,
        get_chain_state(),
        blocks_for_target_calculation
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

    assert {:error, "#{BlockValidation}: Invalid header time"} ==
             BlockValidation.calculate_and_validate_block(
               wrong_time_block,
               prev_block,
               get_chain_state(),
               blocks_for_target_calculation
             )
  end

  test "validate transactions in a block", ctx do
    {sender, priv_key} = Keys.keypair(:sign)
    amount = 5
    fee = 1

    nonce = Account.nonce(TestUtils.get_accounts_chainstate(), sender) + 1

    signed_tx1 =
      Account.spend(sender, priv_key, ctx.receiver, amount, fee, nonce + 1, <<"payload">>)

    signed_tx2 =
      Account.spend(sender, priv_key, ctx.receiver, amount + 5, fee, nonce + 2, <<"payload">>)

    block = %{Genesis.block() | txs: [signed_tx1, signed_tx2]}

    assert block
           |> BlockValidation.validate_block_transactions()
           |> Enum.all?() == true
  end

  def get_new_block(receiver) do
    {sender, priv_key} = Keys.keypair(:sign)
    amount = 100
    fee = 10

    Account.spend(sender, priv_key, receiver, amount, fee, 1000, <<"payload">>)
    block_candidate = Miner.candidate()
    {:ok, new_block} = Miner.mine_sync_block(block_candidate)
    new_block
  end

  def get_prev_block do
    Chain.top_block()
  end

  def get_chain_state do
    Chain.chain_state()
  end
end
