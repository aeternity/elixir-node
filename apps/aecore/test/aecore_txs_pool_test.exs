defmodule AecoreTxsPoolTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.DataTx
  alias Aecore.Wallet.Worker, as: Wallet

  setup wallet do
    path = Application.get_env(:aecore, :persistence)[:path]
    if File.exists?(path) do
      File.rm_rf(path)
    end

    Chain.clear_state()

    on_exit fn ->
      Persistence.delete_all_blocks()
      :ok
    end

    [
      a_pub_key: Wallet.get_public_key(),
      priv_key: Wallet.get_private_key(),
      b_pub_key: Wallet.get_public_key("M/0")
    ]
  end

  @tag timeout: 20_000
  @tag :txs_pool
  test "add transaction, remove it and get pool", wallet do
    # Empty the pool from the other tests
    Pool.get_and_empty_pool()

    nonce1 = Map.get(Chain.chain_state.accounts, wallet.a_pub_key, %{nonce: 0}).nonce + 1
    payload1 = %{to_acc: wallet.b_pub_key,
                 value: 5}
    tx1 = DataTx.init(SpendTx, payload1, wallet.a_pub_key, 10, nonce1)

    nonce2 = nonce1 + 1
    payload2 = %{to_acc: wallet.b_pub_key,
                 value: 5}
    tx2 = DataTx.init(SpendTx, payload2, wallet.a_pub_key, 10, nonce2)

    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, wallet.priv_key)
    {:ok, signed_tx2} = SignedTx.sign_tx(tx2, wallet.priv_key)

    :ok = Miner.mine_sync_block_to_chain()

    assert :ok = Pool.add_transaction(signed_tx1)
    assert :ok = Pool.add_transaction(signed_tx2)
    assert :ok = Pool.remove_transaction(signed_tx2)
    assert Enum.count(Pool.get_pool()) == 1

    :ok = Miner.mine_sync_block_to_chain()
    assert length(Chain.longest_blocks_chain()) > 1
    assert Enum.count(Chain.top_block().txs) == 2
    assert Enum.empty?(Pool.get_pool())
  end

  test "add negative transaction fail", wallet do
    nonce = Map.get(Chain.chain_state.accounts, wallet.a_pub_key, %{nonce: 0}).nonce + 1
    payload = %{to_acc: wallet.b_pub_key,
                value: -5}
    tx1 = DataTx.init(SpendTx, payload, wallet.a_pub_key, 0, nonce)

    {:ok, signed_tx} = SignedTx.sign_tx(tx1, wallet.priv_key)
    assert :error = Pool.add_transaction(signed_tx)
  end
end
