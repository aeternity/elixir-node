defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.TxData

  setup wallet do
    [
      path: File.cwd!
      |> Path.join("test/aewallet/")
      |> Path.join("wallet--2018-1-10-10-49-58"),
      pass: "1234"
    ]
  end

  setup tx do
    to_account = <<4, 234, 31, 124, 43, 123, 54, 65, 213>>
    [
      nonce: Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1,
      lock_time_block: Chain.top_block().header.height +
        Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1,
      wallet_path: File.cwd!
      |> Path.join("test/aewallet/")
      |> Path.join("wallet--2018-1-10-10-49-58"),
      wallet_pass: "1234"
    ]
  end

  @tag :tx
  test "create and verify a signed tx", tx do
    {:ok, from_acc} = Aewallet.Wallet.get_public_key(tx.wallet_path, tx.wallet_pass)
    to_acc = <<4, 234, 31, 124, 43, 123, 54, 65, 213>>
    {:ok, tx_data} = TxData.create(from_acc, to_acc, 5, tx.nonce, 1, tx.lock_time_block)

    {:ok, priv_key} = Aewallet.Wallet.get_private_key(tx.wallet_path, tx.wallet_pass)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    signature = signed_tx.signature
    message = :erlang.term_to_binary(signed_tx.data)
    assert :true = Aewallet.Signing.verify(message, signature, from_acc)
  end

  test "positive tx valid", wallet  do
    {:ok, from_acc} = Aewallet.Wallet.get_public_key(wallet.path, wallet.pass)
    to_acc = <<4, 234, 31, 124, 43, 123, 54, 65, 213>>
    {:ok, tx_data} = TxData.create(from_acc, to_acc, 5,
      Map.get(Chain.chain_state, to_acc, %{nonce: 0}).nonce + 1, 1)

    {:ok, priv_key} = Aewallet.Wallet.get_private_key(wallet.path, wallet.pass)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    signature = signed_tx.signature
    message = :erlang.term_to_binary(signed_tx.data)
    assert :true = Aewallet.Signing.verify(message, signature, from_acc)
  end

  test "negative tx invalid", wallet do
    {:ok, from_acc} = Aewallet.Wallet.get_public_key(wallet.path, wallet.pass)
    to_acc = <<4, 234, 31, 124, 43, 123, 54, 65, 213>>
    {:ok, tx_data} = TxData.create(from_acc, to_acc, -5,
      Map.get(Chain.chain_state, to_acc, %{nonce: 0}).nonce + 1, 1)

    {:ok, priv_key} = Aewallet.Wallet.get_private_key(wallet.path, wallet.pass)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert !SignedTx.is_valid(signed_tx)
  end

  test "coinbase tx invalid", wallet do
    {:ok, from_acc} = Aewallet.Wallet.get_public_key(wallet.path, wallet.pass)
    to_acc = <<4, 234, 31, 124, 43, 123, 54, 65, 213>>
    {:ok, tx_data} = TxData.create(from_acc, to_acc, 5,
      Map.get(Chain.chain_state, to_acc, %{nonce: 0}).nonce + 1, 1)

    {:ok, priv_key} = Aewallet.Wallet.get_private_key(wallet.path, wallet.pass)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert !SignedTx.is_coinbase(signed_tx)
  end
end
