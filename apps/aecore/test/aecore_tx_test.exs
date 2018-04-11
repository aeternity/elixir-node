defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aewallet.Signing
  alias Aeutil.Serialization

  setup do
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

    payload = %{receiver: tx.receiver, amount: amount}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert SignedTx.is_valid?(signed_tx)
    signature = signed_tx.signature
    message = Serialization.pack_binary(signed_tx.data)
    assert true = Signing.verify(message, signature, sender)
  end

  test "negative tx invalid", tx do
    sender = Wallet.get_public_key()
    amount = -5
    fee = 1

    payload = %{receiver: tx.receiver, amount: amount}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert false == SignedTx.is_valid?(signed_tx)
  end

  test "coinbase tx invalid", tx do
    sender = Wallet.get_public_key()
    amount = 5
    fee = 1

    payload = %{receiver: tx.receiver, amount: amount}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert !SignedTx.is_coinbase?(signed_tx)
  end

  test "invalid spend transaction", tx do
    sender = Wallet.get_public_key()
    amount = 200
    fee = 50

    :ok = Miner.mine_sync_block_to_chain()

    assert Enum.count(Chain.chain_state().accounts) == 1
    assert Chain.chain_state().accounts[Wallet.get_public_key()].balance == 100

    payload = %{receiver: tx.receiver, amount: amount}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    :ok = Pool.add_transaction(signed_tx)

    :ok = Miner.mine_sync_block_to_chain()

    # We should have only made two coinbase transactions
    assert Enum.count(Chain.chain_state().accounts) == 1
    assert Chain.chain_state().accounts[Wallet.get_public_key()].balance == 200

    :ok = Miner.mine_sync_block_to_chain()
    # At this poing the sender should have 300 tokens,
    # enough to mine the transaction in the pool

    assert Enum.count(Chain.chain_state().accounts) == 1
    assert Chain.chain_state().accounts[Wallet.get_public_key()].balance == 300

    # This block should add the transaction
    :ok = Miner.mine_sync_block_to_chain()

    assert Enum.count(Chain.chain_state().accounts) == 2
    assert Chain.chain_state().accounts[Wallet.get_public_key()].balance == 200
    assert Chain.chain_state().accounts[tx.receiver].balance == 200
  end

  test "nonce is too small", tx do
    sender = Wallet.get_public_key()
    amount = 200
    fee = 50

    payload = %{receiver: tx.receiver, amount: amount}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, 0)
    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    :ok = Pool.add_transaction(signed_tx)
    :ok = Miner.mine_sync_block_to_chain()
    # the nonce is small or equal to account nonce, so the transaction is invalid
    assert Chain.chain_state().accounts[Wallet.get_public_key()].balance == 100
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

    payload = %{receiver: acc1, amount: amount}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)
    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    :ok = Pool.add_transaction(signed_tx)
    :ok = Miner.mine_sync_block_to_chain()

    # Now acc1 has 80 tokens
    assert Chain.chain_state().accounts[acc1].balance == 80

    amount2 = 50
    fee2 = 40
    # Balance of acc1 is more than amount and fee, send tokens to acc2

    payload2 = %{receiver: acc2, amount: amount2}
    tx_data2 = DataTx.init(SpendTx, payload2, acc1, fee2, 1)
    priv_key2 = Wallet.get_private_key("m/1")
    {:ok, signed_tx2} = SignedTx.sign_tx(tx_data2, priv_key2)

    :ok = Pool.add_transaction(signed_tx2)
    :ok = Miner.mine_sync_block_to_chain()

    # the balance of acc1 and acc2 is not changed because amount + fee > balance of acc1
    assert Chain.chain_state().accounts[acc2] == nil
    assert Chain.chain_state().accounts[acc1].balance == 80
  end
end
