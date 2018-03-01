defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aewallet.Signing
  alias Aeutil.Serialization

  setup wallet do
    [
      to_acc: <<4, 3, 85, 89, 175, 35, 38, 163, 5, 16, 147, 44, 147, 215, 20, 21, 141, 92,
      253, 96, 68, 201, 43, 224, 168, 79, 39, 135, 113, 36, 201, 236, 179, 76, 186,
      91, 130, 3, 145, 215, 221, 167, 128, 23, 63, 35, 140, 174, 35, 233, 188, 120,
      63, 63, 29, 61, 179, 181, 221, 195, 61, 207, 76, 135, 26>>
    ]
  end

  setup tx do
    to_account = <<4, 3, 85, 89, 175, 35, 38, 163, 5, 16, 147, 44, 147, 215, 20, 21, 141, 92,
      253, 96, 68, 201, 43, 224, 168, 79, 39, 135, 113, 36, 201, 236, 179, 76, 186,
      91, 130, 3, 145, 215, 221, 167, 128, 23, 63, 35, 140, 174, 35, 233, 188, 120,
      63, 63, 29, 61, 179, 181, 221, 195, 61, 207, 76, 135, 26>>
    [
      nonce: Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1,
      lock_time_block: Chain.top_block().header.height +
      Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1,
      to_acc: <<4, 3, 85, 89, 175, 35, 38, 163, 5, 16, 147, 44, 147, 215, 20, 21, 141, 92,
      253, 96, 68, 201, 43, 224, 168, 79, 39, 135, 113, 36, 201, 236, 179, 76, 186,
      91, 130, 3, 145, 215, 221, 167, 128, 23, 63, 35, 140, 174, 35, 233, 188, 120,
      63, 63, 29, 61, 179, 181, 221, 195, 61, 207, 76, 135, 26>>
    ]
  end

  @tag :tx
  test "create and verify a signed tx", tx do
    from_acc = Wallet.get_public_key()
    {:ok, tx_data} = SpendTx.create(from_acc, tx.to_acc, 5, tx.nonce, 1, tx.lock_time_block)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    signature = signed_tx.signature
    message = Serialization.pack_binary(signed_tx.data)
    assert :true = Signing.verify(message, signature, from_acc)
  end

  test "positive tx valid", wallet  do
    from_acc = Wallet.get_public_key()
    {:ok, tx_data} = SpendTx.create(from_acc, wallet.to_acc, 5,
      Map.get(Chain.chain_state, wallet.to_acc, %{nonce: 0}).nonce + 1, 1)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    signature = signed_tx.signature
    message = Serialization.pack_binary(signed_tx.data)
    assert :true = Signing.verify(message, signature, from_acc)
  end

  test "negative tx invalid", wallet do
    from_acc = Wallet.get_public_key()
    {:ok, tx_data} = SpendTx.create(from_acc, wallet.to_acc, -5,
      Map.get(Chain.chain_state, wallet.to_acc, %{nonce: 0}).nonce + 1, 1)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert false == SignedTx.is_valid?(signed_tx)
  end

  test "coinbase tx invalid", wallet do
    from_acc = Wallet.get_public_key()
    {:ok, tx_data} = SpendTx.create(from_acc, wallet.to_acc, 5,
      Map.get(Chain.chain_state, wallet.to_acc, %{nonce: 0}).nonce + 1, 1)

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert !SignedTx.is_coinbase?(signed_tx)
  end
end
