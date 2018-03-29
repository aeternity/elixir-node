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
  alias Aecore.Structures.AccountStateTree
  alias Aecore.Structures.Account

  setup do
    Persistence.start_link([])
    Miner.start_link([])
    Chain.clear_state()
    Pool.get_and_empty_pool()

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
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

    assert AccountStateTree.size(Chain.chain_state().accounts) == 1
    assert Account.balance(Chain.chain_state().accounts, Wallet.get_public_key()) == 100

    payload = %{receiver: tx.receiver, amount: amount}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    :ok = Pool.add_transaction(signed_tx)

    :ok = Miner.mine_sync_block_to_chain()

    # We should have only made two coinbase transactions
    assert AccountStateTree.size(Chain.chain_state().accounts) == 1
    assert Account.balance(Chain.chain_state().accounts, Wallet.get_public_key()) == 200

    :ok = Miner.mine_sync_block_to_chain()
    # At this poing the sender should have 300 tokens,
    # enough to mine the transaction in the pool

    assert AccountStateTree.size(Chain.chain_state().accounts) == 1
    assert Account.balance(Chain.chain_state().accounts, Wallet.get_public_key()) == 300

    # This block should add the transaction
    :ok = Miner.mine_sync_block_to_chain()

    assert AccountStateTree.size(Chain.chain_state().accounts) == 2
    assert Account.balance(Chain.chain_state().accounts, Wallet.get_public_key()) == 200
    assert Account.balance(Chain.chain_state().accounts, tx.receiver) == 200
  end
end
