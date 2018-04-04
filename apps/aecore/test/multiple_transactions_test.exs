defmodule MultipleTransactionsTest do
  @moduledoc """
  Unit test for the pool worker module
  """

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Structures.Account

  setup do
    Code.require_file("test_utils.ex", "./test")

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)

    Pool.start_link([])

    [
      account: {Wallet.get_public_key(), Wallet.get_private_key()},
      account2: {Wallet.get_public_key("M/0"), Wallet.get_private_key("m/0")},
      account3: {Wallet.get_public_key("M/1"), Wallet.get_private_key("m/1")},
      account4: {Wallet.get_public_key("M/2"), Wallet.get_private_key("m/2")}
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
    Pool.get_and_empty_pool()

    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()

    nonce1 = Account.nonce(TestUtils.get_accounts_chainstate(), account_pub_key) + 1

    signed_tx1 = create_signed_tx(account, account2, 100, nonce1, 10)

    assert :ok = Pool.add_transaction(signed_tx1)

    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()
    nonce2 = Account.nonce(TestUtils.get_accounts_chainstate(), account2_pub_key) + 1

    signed_tx2 = create_signed_tx(account2, account3, 90, nonce2, 10)

    assert :ok = Pool.add_transaction(signed_tx2)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    assert 0 == Account.balance(TestUtils.get_accounts_chainstate(), account2_pub_key)
    assert 90 == Account.balance(TestUtils.get_accounts_chainstate(), account3_pub_key)

    # account2 => 0; account3 => 90

    # account3 has 90 tokens, spends 90 (+10 fee) to account2 should be invalid
    nonce3 = Account.nonce(TestUtils.get_accounts_chainstate(), account3_pub_key) + 1
    signed_tx3 = create_signed_tx(account3, account2, 90, nonce3, 10)
    assert :ok = Pool.add_transaction(signed_tx3)
    :ok = Miner.mine_sync_block_to_chain()

    # The state of the accounts should be the as same before the invalid tx
    assert 0 == Account.balance(TestUtils.get_accounts_chainstate(), account2_pub_key)
    assert 90 == Account.balance(TestUtils.get_accounts_chainstate(), account3_pub_key)

    Pool.get_and_empty_pool()
    signed_tx4 = create_signed_tx(account, account2, 100, nonce1 + 1, 10)

    assert :ok = Pool.add_transaction(signed_tx4)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 100 == Account.balance(TestUtils.get_accounts_chainstate(), account2_pub_key)

    # acccount2 => 100; account3 => 90

    # account2 has 100 tokens, spends 30 (+10 fee) to account3,
    # and two times 20 (+10 fee) to account4 should succeed

    signed_tx5 = create_signed_tx(account2, account3, 30, nonce2 + 1, 10)
    assert :ok = Pool.add_transaction(signed_tx5)

    signed_tx6 = create_signed_tx(account2, account4, 20, nonce2 + 2, 10)
    assert :ok = Pool.add_transaction(signed_tx6)

    signed_tx7 = create_signed_tx(account2, account4, 20, nonce2 + 3, 10)
    assert :ok = Pool.add_transaction(signed_tx7)

    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    assert 0 == Account.balance(TestUtils.get_accounts_chainstate(), account2_pub_key)
    assert 120 == Account.balance(TestUtils.get_accounts_chainstate(), account3_pub_key)
    assert 40 == Account.balance(TestUtils.get_accounts_chainstate(), account4_pub_key)

    # account2 => 0; account3 => 120; account4 => 40
  end

  @tag timeout: 10_000_000
  @tag :multiple_transaction
  test "in one block, miner collects all the fees from the transactions", setup do
    Chain.clear_state()

    account = setup.account
    account2 = setup.account2
    account3 = setup.account3
    account4 = setup.account4

    {account_pub_key, _account_priv_key} = account
    {account2_pub_key, _account2_priv_key} = account2

    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    nonce1 = Account.nonce(TestUtils.get_accounts_chainstate(), account_pub_key) + 1
    nonce2 = Account.nonce(TestUtils.get_accounts_chainstate(), account2_pub_key) + 1

    signed_tx1 = create_signed_tx(account, account2, 100, nonce1 + 1, 10)
    assert :ok = Pool.add_transaction(signed_tx1)

    signed_tx2 = create_signed_tx(account, account2, 100, nonce1 + 2, 10)
    assert :ok = Pool.add_transaction(signed_tx2)

    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx3 = create_signed_tx(account2, account3, 50, nonce2 + 1, 10)
    assert :ok = Pool.add_transaction(signed_tx3)

    signed_tx4 = create_signed_tx(account2, account4, 50, nonce2 + 2, 10)
    assert :ok = Pool.add_transaction(signed_tx4)

    miner_balance_before_mining =
      Account.balance(TestUtils.get_accounts_chainstate(), account_pub_key)

    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    miner_balance_after_mining =
      Account.balance(TestUtils.get_accounts_chainstate(), account_pub_key)

    assert miner_balance_after_mining ==
             miner_balance_before_mining + Miner.coinbase_transaction_amount() + 20
  end

  defp create_signed_tx(sender, receiver, amount, nonce, fee) do
    {sender_pub_key, sender_priv_key} = sender
    {receiver_pub_key, _receiver_priv_key} = receiver

    payload = %{receiver: receiver_pub_key, amount: amount}
    tx_data = DataTx.init(SpendTx, payload, sender_pub_key, fee, nonce)

    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, sender_priv_key)
    signed_tx
  end
end
