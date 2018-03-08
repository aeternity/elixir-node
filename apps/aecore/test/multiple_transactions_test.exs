defmodule MultipleTransactionsTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Wallet.Worker, as: Wallet

  setup do
    Pool.start_link([])
    []
  end

  @tag timeout: 10_000_000
  @tag :multiple_transaction
  test "in one block" do
    {account1, account2, account3} = get_accounts_one_block()
    {account1_pub_key, _account1_priv_key} = account1
    {account2_pub_key, _account2_priv_key} = account2
    {account3_pub_key, _account3_priv_key} = account3
    from_acc = Wallet.get_public_key()

    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()
    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()

    {:ok, tx1} =
      SpendTx.create(
        from_acc,
        account1_pub_key,
        100,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)

    assert :ok = Pool.add_transaction(signed_tx1)

    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()

    signed_tx2 =
      create_signed_tx(
        account1,
        account2,
        90,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx2)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state()[account1_pub_key].balance
    assert 90 == Chain.chain_state()[account2_pub_key].balance

    # account1 => 0; account2 => 90

    # account A has 100 tokens, spends 100 (+10 fee) to B should be invalid
    {:ok, tx3} =
      SpendTx.create(
        from_acc,
        account1_pub_key,
        100,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    {:ok, signed_tx3} = SignedTx.sign_tx(tx3, priv_key)
    assert :ok = Pool.add_transaction(signed_tx3)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx4 =
      create_signed_tx(
        account1,
        account2,
        100,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx4)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 100 == Chain.chain_state()[account1_pub_key].balance

    # acccount1 => 100; account2 => 90

    # account A has 100 tokens, spends 30 (+10 fee) to B, and two times 20 (+10 fee) to C should succeed

    account1_initial_nonce = Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce
    signed_tx5 = create_signed_tx(account1, account2, 30, account1_initial_nonce + 1, 10)
    assert :ok = Pool.add_transaction(signed_tx5)
    signed_tx6 = create_signed_tx(account1, account3, 20, account1_initial_nonce + 2, 10)
    assert :ok = Pool.add_transaction(signed_tx6)
    signed_tx7 = create_signed_tx(account1, account3, 20, account1_initial_nonce + 3, 10)
    assert :ok = Pool.add_transaction(signed_tx7)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state()[account1_pub_key].balance
    assert 120 == Chain.chain_state()[account2_pub_key].balance
    assert 40 == Chain.chain_state()[account3_pub_key].balance

    # account1 => 0; account2 => 120; account3 => 40

    # account A has 100 tokens, spends 40 (+10 fee) to B, and two times 20 (+10 fee) to C,
    # last transaction to C should be invalid, others be included
    account1_initial_nonce2 = Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce

    {:ok, tx8} =
      SpendTx.create(
        from_acc,
        account1_pub_key,
        100,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    {:ok, signed_tx8} = SignedTx.sign_tx(tx8, priv_key)
    assert :ok = Pool.add_transaction(signed_tx8)
    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()

    signed_tx9 = create_signed_tx(account1, account2, 40, account1_initial_nonce2 + 1, 10)
    assert :ok = Pool.add_transaction(signed_tx9)
    signed_tx10 = create_signed_tx(account1, account3, 20, account1_initial_nonce2 + 2, 10)
    assert :ok = Pool.add_transaction(signed_tx10)
    signed_tx11 = create_signed_tx(account1, account3, 20, account1_initial_nonce2 + 3, 10)
    assert :ok = Pool.add_transaction(signed_tx11)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 20 == Chain.chain_state()[account1_pub_key].balance
    assert 160 == Chain.chain_state()[account2_pub_key].balance
    assert 60 == Chain.chain_state()[account3_pub_key].balance

    # account1 => 20; account2 => 160; account3 => 60

    # account C has 100 tokens, spends 90 (+10 fee) to B, B spends 90 (+10 fee) to A should succeed
    {:ok, tx12} =
      SpendTx.create(
        from_acc,
        account3_pub_key,
        40,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    {:ok, signed_tx12} = SignedTx.sign_tx(tx12, priv_key)
    assert :ok = Pool.add_transaction(signed_tx12)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx13 =
      create_signed_tx(
        account3,
        account2,
        90,
        Map.get(Chain.chain_state(), account3_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx13)

    signed_tx14 =
      create_signed_tx(
        account2,
        account1,
        90,
        Map.get(Chain.chain_state(), account2_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx14)

    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state()[account3_pub_key].balance
    assert 150 == Chain.chain_state()[account2_pub_key].balance
    assert 110 == Chain.chain_state()[account1_pub_key].balance
  end

  @tag timeout: 10_000_000
  @tag :multiple_transaction
  test "in multiple blocks", wallet do
    {account1, account2, account3} = get_accounts_multiple_blocks()
    {account1_pub_key, _account1_priv_key} = account1
    {account2_pub_key, _account2_priv_key} = account2
    {account3_pub_key, _account3_priv_key} = account3
    from_acc = Wallet.get_public_key()

    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()
    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()

    {:ok, tx1} =
      SpendTx.create(
        from_acc,
        account1_pub_key,
        100,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)

    assert :ok = Pool.add_transaction(signed_tx1)
    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()

    signed_tx2 =
      create_signed_tx(
        account1,
        account2,
        90,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx2)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state()[account1_pub_key].balance
    assert 90 == Chain.chain_state()[account2_pub_key].balance

    # account1 => 0; account2 => 90

    # account A has 100 tokens, spends 100 (+10 fee) to B should be invalid
    {:ok, tx3} =
      SpendTx.create(
        from_acc,
        account1_pub_key,
        100,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    {:ok, signed_tx3} = SignedTx.sign_tx(tx3, priv_key)
    assert :ok = Pool.add_transaction(signed_tx3)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx4 =
      create_signed_tx(
        account1,
        account2,
        100,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx4)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 100 == Chain.chain_state()[account1_pub_key].balance

    # acccount1 => 100; account2 => 90

    # account A has 100 tokens, spends 30 (+10 fee) to B, and two times 20 (+10 fee) to C should succeed
    signed_tx5 =
      create_signed_tx(
        account1,
        account2,
        30,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx5)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx6 =
      create_signed_tx(
        account1,
        account3,
        20,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx6)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx7 =
      create_signed_tx(
        account1,
        account3,
        20,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx7)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state()[account1_pub_key].balance
    assert 120 == Chain.chain_state()[account2_pub_key].balance
    assert 40 == Chain.chain_state()[account3_pub_key].balance

    # account1 => 0; account2 => 120; account3 => 40

    # account A has 100 tokens, spends 40 (+10 fee) to B, and two times 20 (+10 fee) to C,
    # last transaction to C should be invalid, others be included
    {:ok, tx8} =
      SpendTx.create(
        from_acc,
        account1_pub_key,
        100,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    {:ok, signed_tx8} = SignedTx.sign_tx(tx8, priv_key)
    assert :ok = Pool.add_transaction(signed_tx8)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx9 =
      create_signed_tx(
        account1,
        account2,
        40,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx9)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx10 =
      create_signed_tx(
        account1,
        account3,
        20,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx10)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx11 =
      create_signed_tx(
        account1,
        account3,
        20,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx11)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 20 == Chain.chain_state()[account1_pub_key].balance
    assert 160 == Chain.chain_state()[account2_pub_key].balance
    assert 60 == Chain.chain_state()[account3_pub_key].balance

    # account1 => 20; account2 => 160; account3 => 60

    # account A has 100 tokens, spends 90 (+10 fee) to B, B spends 90 (+10 fee) to C should succeed
    {:ok, tx12} =
      SpendTx.create(
        from_acc,
        account1_pub_key,
        80,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    {:ok, signed_tx12} = SignedTx.sign_tx(tx12, priv_key)
    assert :ok = Pool.add_transaction(signed_tx12)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx13 =
      create_signed_tx(
        account1,
        account2,
        90,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx13)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx14 =
      create_signed_tx(
        account2,
        account3,
        90,
        Map.get(Chain.chain_state(), account2_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx14)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()
    assert 0 == Chain.chain_state()[account1_pub_key].balance
    assert 150 == Chain.chain_state()[account2_pub_key].balance
    assert 150 == Chain.chain_state()[account3_pub_key].balance
  end

  @tag timeout: 10_000_000
  @tag :multiple_transaction
  test "in one block, miner collects all the fees from the transactions", wallet do
    {account1, account2, account3} = get_accounts_miner_fees()
    {account1_pub_key, _account1_priv_key} = account1
    {account2_pub_key, _account2_priv_key} = account2
    from_acc = Wallet.get_public_key()

    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()

    {:ok, tx1} =
      SpendTx.create(
        from_acc,
        account1_pub_key,
        100,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)

    assert :ok = Pool.add_transaction(signed_tx1)

    {:ok, tx2} =
      SpendTx.create(
        from_acc,
        account2_pub_key,
        100,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 2,
        10
      )

    {:ok, signed_tx2} = SignedTx.sign_tx(tx2, priv_key)
    assert :ok = Pool.add_transaction(signed_tx2)
    :ok = Miner.mine_sync_block_to_chain()

    Pool.get_and_empty_pool()

    signed_tx3 =
      create_signed_tx(
        account1,
        account3,
        90,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx3)

    signed_tx4 =
      create_signed_tx(
        account2,
        account3,
        90,
        Map.get(Chain.chain_state(), account2_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    assert :ok = Pool.add_transaction(signed_tx4)
    miner_balance_before_mining = Map.get(Chain.chain_state(), from_acc).balance
    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()
    miner_balance_after_mining = Map.get(Chain.chain_state(), from_acc).balance

    assert miner_balance_after_mining ==
             miner_balance_before_mining + Miner.coinbase_transaction_value() + 20
  end

  @tag timeout: 10_000_000
  test "locked amount", wallet do
    from_acc = Wallet.get_public_key()
    account1 = get_account_locked_amount()
    {account1_pub_key, _account1_priv_key} = account1

    :ok = Miner.mine_sync_block_to_chain()
    Pool.get_and_empty_pool()

    {:ok, tx1} =
      SpendTx.create(
        from_acc,
        account1_pub_key,
        90,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10,
        Chain.top_block().header.height +
          Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 3
      )

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)

    Pool.add_transaction(signed_tx1)
    :ok = Miner.mine_sync_block_to_chain()

    signed_tx2 =
      create_signed_tx(
        account1,
        {from_acc, priv_key},
        50,
        Map.get(Chain.chain_state(), account1_pub_key, %{nonce: 0}).nonce + 1,
        10
      )

    Pool.add_transaction(signed_tx2)
    :ok = Miner.mine_sync_block_to_chain()

    assert Enum.count(Pool.get_pool()) == 1
    :ok = Miner.mine_sync_block_to_chain()
    assert Enum.count(Pool.get_pool()) == 1
    assert Map.get(Chain.chain_state(), account1_pub_key).balance == 90
    miner_balance_before_block = Map.get(Chain.chain_state(), from_acc).balance
    :ok = Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Pool.get_pool())
    miner_balance_after_block = Map.get(Chain.chain_state(), from_acc).balance
    assert miner_balance_after_block == miner_balance_before_block + 100 + 60
  end

  defp get_accounts_one_block() do
    account1 = {
      Wallet.get_public_key("M/0/0"),
      Wallet.get_private_key("m/0/0")
    }

    account2 = {
      Wallet.get_public_key("M/0/1"),
      Wallet.get_private_key("m/0/1")
    }

    account3 = {
      Wallet.get_public_key("M/0/2"),
      Wallet.get_private_key("m/0/2")
    }

    {account1, account2, account3}
  end

  defp get_accounts_multiple_blocks() do
    account1 = {
      Wallet.get_public_key("M/0/3"),
      Wallet.get_private_key("m/0/3")
    }

    account2 = {
      Wallet.get_public_key("M/0/4"),
      Wallet.get_private_key("m/0/4")
    }

    account3 = {
      Wallet.get_public_key("M/0/5"),
      Wallet.get_private_key("m/0/5")
    }

    {account1, account2, account3}
  end

  defp get_accounts_miner_fees() do
    account1 = {
      Wallet.get_public_key("M/0/6"),
      Wallet.get_private_key("m/0/6")
    }

    account2 = {
      Wallet.get_public_key("M/0/7"),
      Wallet.get_private_key("m/0/7")
    }

    account3 = {
      Wallet.get_public_key("M/0/8"),
      Wallet.get_private_key("m/0/8")
    }

    {account1, account2, account3}
  end

  defp get_account_locked_amount() do
    {
      Wallet.get_public_key("M/0/9"),
      Wallet.get_private_key("m/0/9")
    }
  end

  defp create_signed_tx(from_acc, to_acc, value, nonce, fee, lock_time_block \\ 0) do
    {from_acc_pub_key, from_acc_priv_key} = from_acc
    {to_acc_pub_key, _to_acc_priv_key} = to_acc

    {:ok, tx_data} =
      SpendTx.create(from_acc_pub_key, to_acc_pub_key, value, nonce, fee, lock_time_block)

    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, from_acc_priv_key)
    signed_tx
  end
end
