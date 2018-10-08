defmodule MultipleTransactionsTest do
  @moduledoc """
  Unit test for the pool worker module
  """

  use ExUnit.Case

  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys
  alias Aecore.Account.Account
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Governance.GovernanceConstants

  setup do
    Code.require_file("test_utils.ex", "./test")

    Persistence.delete_all()

    TestUtils.clean_blockchain()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  setup do
    %{public: acc2_pub, secret: acc2_priv} = :enacl.sign_keypair()
    %{public: acc3_pub, secret: acc3_priv} = :enacl.sign_keypair()
    %{public: acc4_pub, secret: acc4_priv} = :enacl.sign_keypair()
    {pubkey, privkey} = Keys.keypair(:sign)

    [
      account: {pubkey, privkey},
      account2: {acc2_pub, acc2_priv},
      account3: {acc3_pub, acc3_priv},
      account4: {acc4_pub, acc4_priv}
    ]
  end

  @tag timeout: 10_000_000
  @tag :multiple_transaction
  test "in one block", setup do
    Chain.clear_state()

    account = setup.account
    account2 = setup.account2
    account3 = setup.account3
    account4 = setup.account4
    {account_pub_key, _account_priv_key} = account
    {account2_pub_key, _account2_priv_key} = account2
    {account3_pub_key, _account3_priv_key} = account3
    {account4_pub_key, _account4_priv_key} = account4

    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()

    nonce1 = Account.nonce(TestUtils.get_accounts_chainstate(), account_pub_key) + 1

    create_signed_tx(account, account2, 100, nonce1, 10)

    :ok = Miner.mine_sync_block_to_chain()
    assert %{} == Pool.get_and_empty_pool()
    assert 100 == Account.balance(TestUtils.get_accounts_chainstate(), account2_pub_key)
    nonce2 = Account.nonce(TestUtils.get_accounts_chainstate(), account2_pub_key) + 1

    create_signed_tx(account2, account3, 90, nonce2, 10)
    :ok = Miner.mine_sync_block_to_chain()

    assert %{} == Pool.get_and_empty_pool()
    assert 0 == Account.balance(TestUtils.get_accounts_chainstate(), account2_pub_key)
    assert 90 == Account.balance(TestUtils.get_accounts_chainstate(), account3_pub_key)

    # account2 => 0; account3 => 90

    # account3 has 90 tokens, spends 90 (+10 fee) to account2 should be invalid
    nonce3 = Account.nonce(TestUtils.get_accounts_chainstate(), account3_pub_key) + 1
    create_signed_tx(account3, account2, 90, nonce3, 10)
    :ok = Miner.mine_sync_block_to_chain()

    # The state of the accounts should be the as same before the invalid tx
    assert 0 == Account.balance(TestUtils.get_accounts_chainstate(), account2_pub_key)
    assert 90 == Account.balance(TestUtils.get_accounts_chainstate(), account3_pub_key)

    Pool.get_and_empty_pool()
    create_signed_tx(account, account2, 100, nonce1 + 1, 10)

    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 100 == Account.balance(TestUtils.get_accounts_chainstate(), account2_pub_key)

    # acccount2 => 100; account3 => 90

    # account2 has 100 tokens, spends 30 (+10 fee) to account3,
    # and two times 20 (+10 fee) to account4 should succeed

    create_signed_tx(account2, account3, 30, nonce2 + 1, 10)
    create_signed_tx(account2, account4, 20, nonce2 + 2, 10)
    create_signed_tx(account2, account4, 20, nonce2 + 3, 10)

    :ok = Miner.mine_sync_block_to_chain()

    assert %{} == Pool.get_and_empty_pool()

    assert 0 == Account.balance(TestUtils.get_accounts_chainstate(), account2_pub_key)
    assert 120 == Account.balance(TestUtils.get_accounts_chainstate(), account3_pub_key)
    assert 40 == Account.balance(TestUtils.get_accounts_chainstate(), account4_pub_key)

    # account2 => 0; account3 => 120; account4 => 40
  end

  @tag timeout: 10_000_000
  @tag :multiple_transaction
  test "in one block, miner collects all the fees from the transactions", setup do
    Chain.clear_state()
    Pool.get_and_empty_pool()

    account = setup.account
    account2 = setup.account2
    account3 = setup.account3
    account4 = setup.account4

    {account_pub_key, _account_priv_key} = account
    {account2_pub_key, _account2_priv_key} = account2

    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()

    assert %{} == Pool.get_and_empty_pool()

    nonce1 = Account.nonce(TestUtils.get_accounts_chainstate(), account_pub_key) + 1
    nonce2 = Account.nonce(TestUtils.get_accounts_chainstate(), account2_pub_key) + 1

    create_signed_tx(account, account2, 100, nonce1 + 1, 10)
    create_signed_tx(account, account2, 100, nonce1 + 2, 10)

    :ok = Miner.mine_sync_block_to_chain()

    assert %{} == Pool.get_and_empty_pool()

    create_signed_tx(account2, account3, 50, nonce2 + 1, 10)
    create_signed_tx(account2, account4, 50, nonce2 + 2, 10)

    miner_balance_before_mining =
      Account.balance(TestUtils.get_accounts_chainstate(), account_pub_key)

    :ok = Miner.mine_sync_block_to_chain()

    assert %{} == Pool.get_and_empty_pool()

    miner_balance_after_mining =
      Account.balance(TestUtils.get_accounts_chainstate(), account_pub_key)

    assert miner_balance_after_mining ==
             miner_balance_before_mining + GovernanceConstants.coinbase_transaction_amount() + 20
  end

  defp create_signed_tx(sender, receiver, amount, nonce, fee) do
    {sender_pub_key, sender_priv_key} = sender
    {receiver_pub_key, _receiver_priv_key} = receiver

    Account.spend(
      sender_pub_key,
      sender_priv_key,
      receiver_pub_key,
      amount,
      fee,
      nonce,
      <<"payload">>
    )
  end
end
