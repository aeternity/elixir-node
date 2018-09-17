defmodule AecoreTxTest do
  @moduledoc """
  Unit tests for the Aecore.Tx.Tx module
  """

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Tx.{SignedTx, DataTx}
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Account.Account
  alias Aecore.Governance.GovernanceConstants, as: Governance
  alias Aecore.Keys

  setup do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  setup _tx do
    {sender_acc, _} = Keys.keypair(:sign)
    %{public: receiver} = :enacl.sign_keypair()

    [
      nonce: Map.get(Chain.chain_state(), sender_acc, %{nonce: 0}).nonce + 1,
      receiver: receiver
    ]
  end

  test "positive tx valid", tx do
    {sender, _} = Keys.keypair(:sign)
    amount = 5
    fee = 1

    payload = %{receiver: tx.receiver, amount: amount, version: 1, payload: <<"payload">>}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    {_, priv_key} = Keys.keypair(:sign)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    assert :ok = SignedTx.validate(signed_tx)
    [signature] = signed_tx.signatures

    message = DataTx.rlp_encode(signed_tx.data)
    assert true = Keys.verify(message, signature, sender)
  end

  @tag :test_test
  test "negative DataTx invalid", tx do
    {sender, _} = Keys.keypair(:sign)
    amount = -5
    fee = 1

    payload = %{receiver: tx.receiver, amount: amount, version: 1, payload: <<"some payload">>}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    assert {:error, "#{SpendTx}: The amount cannot be a negative number"} ==
             DataTx.validate(tx_data)
  end

  test "invalid spend transaction", tx do
    reward = Governance.coinbase_transaction_amount()
    {sender, priv_key} = Keys.keypair(:sign)
    amount = reward * 2
    fee = 50

    :ok = Miner.mine_sync_block_to_chain()
    assert Account.balance(Chain.chain_state().accounts, sender) == reward

    payload = %{receiver: tx.receiver, amount: amount, version: 1, payload: <<"payload">>}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)

    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    :ok = Pool.add_transaction(signed_tx)

    :ok = Miner.mine_sync_block_to_chain()

    assert Account.balance(Chain.chain_state().accounts, sender) == amount

    :ok = Miner.mine_sync_block_to_chain()
    # At this poing the sender should have (reward * 3) tokens,
    # enough to mine the transaction in the pool

    assert Account.balance(Chain.chain_state().accounts, sender) == reward * 3

    # This block should add the transaction
    :ok = Miner.mine_sync_block_to_chain()

    assert Account.balance(TestUtils.get_accounts_chainstate(), sender) ==
             Account.balance(TestUtils.get_accounts_chainstate(), tx.receiver)
  end

  test "nonce is too small", tx do
    {sender, priv_key} = Keys.keypair(:sign)
    amount = 200
    fee = 50

    payload = %{receiver: tx.receiver, amount: amount, version: 1, payload: <<"payload">>}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, 0)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    :ok = Pool.add_transaction(signed_tx)
    :ok = Miner.mine_sync_block_to_chain()
    # the nonce is small or equal to account nonce, so the transaction is invalid
    assert Account.balance(TestUtils.get_accounts_chainstate(), sender) ==
             10_000_000_000_000_000_000
  end

  test "sender pub_key is too small", tx do
    # Use private as public key for sender to get error that sender key is not 33 bytes
    {_, sender} = Keys.keypair(:sign)
    refute byte_size(sender) == 32
    amount = 100
    fee = 50

    :ok = Miner.mine_sync_block_to_chain()
    payload = %{receiver: tx.receiver, amount: amount, version: 1, payload: <<"payload">>}

    data_tx = DataTx.init(SpendTx, payload, sender, fee, 1)
    {:error, _} = DataTx.validate(data_tx)
  end

  test "receiver pub_key is too small" do
    {sender, _} = Keys.keypair(:sign)
    amount = 100
    fee = 50

    # Use private as public key for receiver to get error that receiver key is not 32 bytes
    {_, receiver} = Keys.keypair(:sign)
    refute byte_size(receiver) == 32
    :ok = Miner.mine_sync_block_to_chain()
    payload = %{receiver: receiver, amount: amount, version: 1, payload: <<"payload">>}

    data_tx = DataTx.init(SpendTx, payload, sender, fee, 1)
    {:error, _} = DataTx.validate(data_tx)
  end

  test "sum of amount and fee more than balance", tx do
    {sender, priv_key} = Keys.keypair(:sign)
    %{public: acc1, secret: priv_key2} = :enacl.sign_keypair()
    %{public: acc2} = :enacl.sign_keypair()
    amount = 80
    fee = 40

    :ok = Miner.mine_sync_block_to_chain()
    :ok = Miner.mine_sync_block_to_chain()
    # Send tokens to the first account, sender has 200 tokens

    payload = %{receiver: acc1, amount: amount, version: 1, payload: <<"payload">>}
    tx_data = DataTx.init(SpendTx, payload, sender, fee, tx.nonce)
    {:ok, signed_tx} = SignedTx.sign_tx(tx_data, priv_key)

    :ok = Pool.add_transaction(signed_tx)
    :ok = Miner.mine_sync_block_to_chain()

    # Now acc1 has 80 tokens
    assert Account.balance(Chain.chain_state().accounts, acc1) == 80

    amount2 = 50
    fee2 = 40
    # Balance of acc1 is more than amount and fee, send tokens to acc2

    payload2 = %{receiver: acc2, amount: amount2, version: 1, payload: <<"payload">>}
    tx_data2 = DataTx.init(SpendTx, payload2, acc1, fee2, 1)
    {:ok, signed_tx2} = SignedTx.sign_tx(tx_data2, priv_key2)

    :ok = Pool.add_transaction(signed_tx2)
    :ok = Miner.mine_sync_block_to_chain()

    # the balance of acc1 and acc2 is not changed because amount + fee > balance of acc1
    assert Account.balance(Chain.chain_state().accounts, acc2) == 0
    assert Account.balance(Chain.chain_state().accounts, acc1) == 80
  end
end
