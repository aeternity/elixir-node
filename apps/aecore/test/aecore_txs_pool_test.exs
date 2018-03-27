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
  alias Aecore.Structures.Account

  setup wallet do
    path = Application.get_env(:aecore, :persistence)[:path]

    if File.exists?(path) do
      File.rm_rf(path)
    end

    Chain.clear_state()

    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)

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

    nonce1 = Map.get(Chain.chain_state().accounts, wallet.a_pub_key, %{nonce: 0}).nonce + 1

    {:ok, signed_tx1} =
      Account.spend(wallet.a_pub_key, wallet.priv_key, wallet.b_pub_key, 5, 10, nonce1)

    {:ok, signed_tx2} =
      Account.spend(wallet.a_pub_key, wallet.priv_key, wallet.b_pub_key, 5, 10, nonce1 + 1)

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
    nonce = Map.get(Chain.chain_state().accounts, wallet.a_pub_key, %{nonce: 0}).nonce + 1

    {:ok, signed_tx} =
      Account.spend(wallet.a_pub_key, wallet.priv_key, wallet.b_pub_key, -5, 10, nonce)

    assert :error = Pool.add_transaction(signed_tx)
  end
end
