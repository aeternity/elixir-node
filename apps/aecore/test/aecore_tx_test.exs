defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aewallet.Signing
  alias Aeutil.Serialization

  setup tx do
    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)

    receiver_acc = Wallet.get_public_key("M/0")

    [
      nonce: Map.get(Chain.chain_state(), receiver_acc, %{nonce: 0}).nonce + 1,
      lock_time_block:
        Chain.top_block().header.height +
          Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1,
      receiver: Wallet.get_public_key("M/0")
    ]
  end

  test "positive tx valid", tx do
    sender = Wallet.get_public_key()
    amount = 5
    fee = 1

    payload = %{receiver: tx.receiver, amount: amount, lock_time_block: tx.lock_time_block}
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

    payload = %{receiver: tx.receiver, amount: amount, lock_time_block: tx.lock_time_block}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert false == SignedTx.is_valid?(signed_tx)
  end

  test "coinbase tx invalid", tx do
    sender = Wallet.get_public_key()
    amount = 5
    fee = 1

    payload = %{receiver: tx.receiver, amount: amount, lock_time_block: tx.lock_time_block}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert !SignedTx.is_coinbase?(signed_tx)
  end
end
