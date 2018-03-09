defmodule MultipleTransactionsTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Wallet.Worker, as: Wallet

  setup do
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
    init_test()
    Chain.clear_state()

    account = setup.account
    account2 = setup.account2
    account3 = setup.account3
    account4 = setup.account4
    {account_pub_key, account_priv_key} = account
    {account2_pub_key, account2_priv_key} = account2
    {account3_pub_key, account3_priv_key} = account3
    {account4_pub_key, account4_priv_key} = account4

    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()

    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()

    nonce1 = Map.get(Chain.chain_state.accounts, account_pub_key, %{nonce: 0}).nonce + 1

    signed_tx1 = create_signed_tx(account, account2, 100, nonce1, 10)

    assert :ok = Pool.add_transaction(signed_tx1)

    :ok = Miner.mine_sync_block_to_chain
    Pool.get_and_empty_pool()

    nonce2 = Map.get(Chain.chain_state.accounts, account2_pub_key, %{nonce: 0}).nonce + 1
    signed_tx2 = create_signed_tx(account2, account3, 90, nonce2, 10)

    assert :ok = Pool.add_transaction(signed_tx2)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state.accounts[account2_pub_key].balance
    assert 90 == Chain.chain_state.accounts[account3_pub_key].balance

    # account2 => 0; account3 => 90

    # account3 has 90 tokens, spends 90 (+10 fee) to account2 should be invalid

    nonce3 = Map.get(Chain.chain_state.accounts, account3_pub_key, %{nonce: 0}).nonce + 1
    signed_tx3 = create_signed_tx(account3, account2, 90, nonce3, 10)
    assert :ok = Pool.add_transaction(signed_tx3)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    signed_tx4 = create_signed_tx(account, account2, 100, nonce1 + 1, 10)

    assert :ok = Pool.add_transaction(signed_tx4)
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 100 == Chain.chain_state.accounts[account2_pub_key].balance

    # acccount2 => 100; account3 => 90

    # account2 has 100 tokens, spends 30 (+10 fee) to account3,
    # and two times 20 (+10 fee) to account4 should succeed

    signed_tx5 = create_signed_tx(account2, account3, 30, nonce2 + 1, 10)
    assert :ok = Pool.add_transaction(signed_tx5)

    signed_tx6 = create_signed_tx(account2, account4, 20, nonce2 + 2, 10)
    assert :ok = Pool.add_transaction(signed_tx6)

    signed_tx7 = create_signed_tx(account2, account4, 20, nonce2 + 3, 10)
    assert :ok = Pool.add_transaction(signed_tx7)

    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state.accounts[account2_pub_key].balance
    assert 120 == Chain.chain_state.accounts[account3_pub_key].balance
    assert 40 == Chain.chain_state.accounts[account4_pub_key].balance

    # account2 => 0; account3 => 120; account4 => 40
  end

  @tag timeout: 10_000_000
  @tag :multiple_transaction
  test "in one block, miner collects all the fees from the transactions", setup do
    init_test()
    Chain.clear_state()

    account = setup.account
    account2 = setup.account2
    account3 = setup.account3
    account4 = setup.account4
    {account_pub_key, account_priv_key} = account
    {account2_pub_key, account2_priv_key} = account2
    {account3_pub_key, account3_priv_key} = account3
    {account4_pub_key, account4_priv_key} = account4

    :ok = Miner.mine_sync_block_to_chain
    :ok = Miner.mine_sync_block_to_chain
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()

    nonce1 = Map.get(Chain.chain_state.accounts, account_pub_key, %{nonce: 0}).nonce
    nonce2 = Map.get(Chain.chain_state.accounts, account2_pub_key, %{nonce: 0}).nonce

    signed_tx1 = create_signed_tx(account, account2, 100, nonce1 + 1, 10)
    assert :ok = Pool.add_transaction(signed_tx1)

    signed_tx2 = create_signed_tx(account, account2, 100, nonce1 + 2, 10)
    assert :ok = Pool.add_transaction(signed_tx2)

    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()

    signed_tx3 = create_signed_tx(account2, account3, 50, nonce2 + 1, 10)
    assert :ok = Pool.add_transaction(signed_tx3)

    signed_tx4 = create_signed_tx(account2, account4, 50, nonce2 + 2, 10)
    assert :ok = Pool.add_transaction(signed_tx4)

    miner_balance_before_mining = Chain.chain_state.accounts[account_pub_key].balance
    :ok = Miner.mine_sync_block_to_chain

    Pool.get_and_empty_pool()
    miner_balance_after_mining = Chain.chain_state.accounts[account_pub_key].balance
    assert miner_balance_after_mining ==
      miner_balance_before_mining + Miner.coinbase_transaction_value() + 20
  end

  defp create_signed_tx(from_acc, to_acc, value, nonce, fee, lock_time_block \\ 0) do
    {from_acc_pub_key, from_acc_priv_key} = from_acc
    {to_acc_pub_key, _to_acc_priv_key} = to_acc

    payload = %{to_acc: to_acc_pub_key, value: value, lock_time_block: lock_time_block}
    tx_data = DataTx.init(SpendTx, payload, from_acc_pub_key, fee, nonce)

    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, from_acc_priv_key)
    signed_tx
  end

  def init_test() do
    path = Application.get_env(:aecore, :persistence)[:path]
    if File.exists?(path) do
      File.rm_rf(path)
    end
  end

end
