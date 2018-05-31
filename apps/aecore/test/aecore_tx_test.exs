defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Tx.Tx module
  """

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aewallet.Signing
  alias Aeutil.Serialization
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Account

  setup do
    Code.require_file("test_utils.ex", "./test")

    Persistence.start_link([])
    Miner.start_link([])
    Chain.clear_state()
    Pool.get_and_empty_pool()

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      Pool.get_and_empty_pool()
      :ok
    end)
  end

  setup tx do
    sender_acc = Wallet.get_public_key()

    [
      nonce: Map.get(Chain.chain_state(), sender_acc, %{nonce: 0}).nonce + 1,
      receiver: Wallet.get_public_key("M/0")
    ]
  end

  test "positive tx valid", tx do
    sender = Wallet.get_public_key()
    amount = 5
    fee = 1

    payload = %{receiver: tx.receiver, amount: amount, version: 1, payload: <<"payload">>}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, sender, priv_key)

    assert :ok = SignedTx.validate(signed_tx)
    [signature] = signed_tx.signatures
    message = Serialization.rlp_encode(signed_tx.data, :tx)
    assert true = Signing.verify(message, signature, sender)
  end

  @tag :test_test
  test "negative DataTx invalid", tx do
    sender = Wallet.get_public_key()
    amount = -5
    fee = 1

    payload = %{receiver: tx.receiver, amount: amount, version: 1, payload: <<"some payload">>}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)
    priv_key = Wallet.get_private_key()

    assert {:error, "#{SpendTx}: The amount cannot be a negative number"} ==
             DataTx.validate(tx_data)
  end

  test "invalid spend transaction", tx do
    sender = Wallet.get_public_key()
    amount = 200
    fee = 50

    :ok = Miner.mine_sync_block_to_chain()
    assert Account.balance(Chain.chain_state().accounts, Wallet.get_public_key()) == 100

    payload = %{receiver: tx.receiver, amount: amount, version: 1, payload: <<"payload">>}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, sender, priv_key)

    :ok = Pool.add_transaction(signed_tx)

    :ok = Miner.mine_sync_block_to_chain()

    assert Account.balance(Chain.chain_state().accounts, Wallet.get_public_key()) == 200

    :ok = Miner.mine_sync_block_to_chain()
    # At this poing the sender should have 300 tokens,
    # enough to mine the transaction in the pool

    assert Account.balance(Chain.chain_state().accounts, Wallet.get_public_key()) == 300

    # This block should add the transaction
    :ok = Miner.mine_sync_block_to_chain()

    assert Account.balance(TestUtils.get_accounts_chainstate(), Wallet.get_public_key()) == 200
    assert Account.balance(Chain.chain_state().accounts, tx.receiver) == 200
  end

  test "nonce is too small", tx do
    sender = Wallet.get_public_key()
    amount = 200
    fee = 50

    payload = %{receiver: tx.receiver, amount: amount, version: 1, payload: <<"payload">>}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, 0)
    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, sender, priv_key)

    :ok = Pool.add_transaction(signed_tx)
    :ok = Miner.mine_sync_block_to_chain()
    # the nonce is small or equal to account nonce, so the transaction is invalid
    assert Account.balance(TestUtils.get_accounts_chainstate(), Wallet.get_public_key()) == 100
  end

  test "sender pub_key is too small", tx do
    # Use private as public key for sender to get error that sender key is not 33 bytes
    sender = Wallet.get_private_key()
    refute byte_size(sender) == 33
    amount = 100
    fee = 50

    :ok = Miner.mine_sync_block_to_chain()
    payload = %{receiver: tx.receiver, amount: amount, version: 1, payload: <<"payload">>}

    data_tx = DataTx.init(SpendTx, payload, sender, fee, 1)
    {:error, _} = DataTx.validate(data_tx)
  end

  test "receiver pub_key is too small", tx do
    sender = Wallet.get_public_key()
    amount = 100
    fee = 50

    # Use private as public key for receiver to get error that receiver key is not 33 bytes
    receiver = Wallet.get_private_key("M/0")
    refute byte_size(receiver) == 33
    :ok = Miner.mine_sync_block_to_chain()
    payload = %{receiver: receiver, amount: amount, version: 1, payload: <<"payload">>}

    data_tx = DataTx.init(SpendTx, payload, sender, fee, 1)
    {:error, _} = DataTx.validate(data_tx)
  end

  test "sum of amount and fee more than balance", tx do
    sender = Wallet.get_public_key()
    acc1 = Wallet.get_public_key("M/1")
    acc2 = Wallet.get_public_key("M/2")
    amount = 80
    fee = 40

    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()
    # Send tokens to the first account, sender has 200 tokens

    payload = %{receiver: acc1, amount: amount, version: 1, payload: <<"payload">>}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)
    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, sender, priv_key)

    :ok = Pool.add_transaction(signed_tx)
    :ok = Miner.mine_sync_block_to_chain()

    # Now acc1 has 80 tokens
    assert Account.balance(Chain.chain_state().accounts, acc1) == 80

    amount2 = 50
    fee2 = 40
    # Balance of acc1 is more than amount and fee, send tokens to acc2

    payload2 = %{receiver: acc2, amount: amount2, version: 1, payload: <<"payload">>}
    tx_data2 = DataTx.init(SpendTx, payload2, acc1, fee2, 1)
    priv_key2 = Wallet.get_private_key("m/1")
    {:ok, signed_tx2} = SignedTx.sign_tx(tx_data2, acc1, priv_key2)

    :ok = Pool.add_transaction(signed_tx2)
    :ok = Miner.mine_sync_block_to_chain()

    # the balance of acc1 and acc2 is not changed because amount + fee > balance of acc1
    assert Account.balance(Chain.chain_state().accounts, acc2) == 0
    assert Account.balance(Chain.chain_state().accounts, acc1) == 80
  end
end
