defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Txs.Tx module
  """

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SignedTx

  setup wallet do
    ## TODO: This dir should be changed to be in the test folder,
    ## because othersize when we build the project again this wallet file
    ## will not exist!!!
    dir = Application.get_env(:aecore, :aewallet)[:path]
    [
      path: Path.join(dir, "wallet--2018-1-9-15-32-15"),
      pass: "1234"
    ]
  end

  setup tx do
    to_account = <<4, 234, 31, 124, 43, 123, 54, 65, 213>>
    [
      nonce: Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1,
      lock_time_block: Chain.top_block().header.height +
        Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1
    ]
  end

  @tag :tx
  test "create and verify a signed tx", tx do
    to_account = <<4, 234, 31, 124, 43, 123, 54, 65, 213>>
    {:ok, signed_tx} = SignedTx.sign_tx(to_account, 5, tx.nonce, 1, tx.lock_time_block)

    pub_key = signed_tx.data.from_acc
    signature = signed_tx.signature
    message = :erlang.term_to_binary(signed_tx.data)
    assert :true = Aewallet.Signing.verify(message, signature, pub_key)
  end

  test "positive tx valid", wallet  do
    {:ok, to_account} = Aewallet.Wallet.get_public_key(wallet.path, wallet.pass)
    {:ok, tx} = SignedTx.sign_tx(to_account, 5,
      Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 1)

    pub_key = tx.data.from_acc
    signature = tx.signature
    message = :erlang.term_to_binary(tx.data)
    assert :true = Aewallet.Signing.verify(message, signature, pub_key)
  end

  test "negative tx invalid", wallet do
    {:ok, to_account} = Aewallet.Wallet.get_public_key(wallet.path, wallet.pass)
    {:ok, tx} = SignedTx.sign_tx(to_account, -5,
      Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 1)

    pub_key = tx.data.from_acc
    signature = tx.signature
    message = :erlang.term_to_binary(tx.data)
    assert !SignedTx.is_valid(tx)
  end

  test "coinbase tx invalid", wallet do
    {:ok, to_account} = Aewallet.Wallet.get_public_key(wallet.path, wallet.pass)
    {:ok, tx} = SignedTx.sign_tx(to_account, 5,
      Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 1)

    pub_key = tx.data.from_acc
    signature = tx.signature
    message = :erlang.term_to_binary(tx.data)
    assert !SignedTx.is_coinbase(tx)
  end
end
