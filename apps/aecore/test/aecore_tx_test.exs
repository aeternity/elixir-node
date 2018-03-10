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
    on_exit fn ->
      Persistence.delete_all_blocks()
      :ok
    end
    to_account = Wallet.get_public_key("M/0")
    [
      nonce: Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1,
      lock_time_block: Chain.top_block().header.height +
      Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1,
      to_acc: Wallet.get_public_key("M/0")
    ]
  end

  test "positive tx valid", tx  do
    from_acc = Wallet.get_public_key()
    value = 5
    fee = 1

    payload = %{to_acc: tx.to_acc, value: value, lock_time_block: tx.lock_time_block}
    tx_data = DataTx.init(SpendTx, payload, from_acc, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    signature = signed_tx.signature
    message = Serialization.pack_binary(signed_tx.data)
    assert :true = Signing.verify(message, signature, from_acc)
  end

  test "negative tx invalid", tx do
    from_acc = Wallet.get_public_key()
    value = -5
    fee = 1

    payload = %{to_acc: tx.to_acc, value: value, lock_time_block: tx.lock_time_block}
    tx_data = DataTx.init(SpendTx, payload, from_acc, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert false == SignedTx.is_valid?(signed_tx)
  end

  test "coinbase tx invalid", tx do
    from_acc = Wallet.get_public_key()
    value = 5
    fee = 1

    payload = %{to_acc: tx.to_acc, value: value, lock_time_block: tx.lock_time_block}
    tx_data = DataTx.init(SpendTx, payload, from_acc, fee, tx.nonce)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert !SignedTx.is_coinbase?(signed_tx)
  end
end
