defmodule AecoreTxsPoolTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Wallet.Worker, as: Wallet

  setup ctx do
    [
      to_acc: Wallet.get_public_key()
    ]
  end

  @tag timeout: 20_000
  @tag :txs_pool
  test "add transaction, remove it and get pool", ctx do
    # Empty the pool from the other tests
    Pool.get_and_empty_pool()

    from_acc = Wallet.get_public_key()

    {:ok, tx1} =
      SpendTx.create(
        from_acc,
        ctx.to_acc,
        5,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    {:ok, tx2} =
      SpendTx.create(
        from_acc,
        ctx.to_acc,
        5,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 2,
        10
      )

    :ok = Miner.mine_sync_block_to_chain()

    priv_key = Wallet.get_private_key()

    {:ok, signed_tx1} = SignedTx.sign_tx(tx1, priv_key)
    {:ok, signed_tx2} = SignedTx.sign_tx(tx2, priv_key)

    assert :ok = Pool.add_transaction(signed_tx1)
    assert :ok = Pool.add_transaction(signed_tx2)
    assert :ok = Pool.remove_transaction(signed_tx2)
    assert Enum.count(Pool.get_pool()) == 1

    :ok = Miner.mine_sync_block_to_chain()

    assert length(Chain.longest_blocks_chain()) > 1
    assert Enum.count(Chain.top_block().txs) == 2
    assert Enum.empty?(Pool.get_pool())
  end

  test "add negative transaction fail", ctx do
    from_acc = Wallet.get_public_key()

    {:ok, tx} =
      SpendTx.create(
        from_acc,
        ctx.to_acc,
        -5,
        Map.get(Chain.chain_state(), from_acc, %{nonce: 0}).nonce + 1,
        10
      )

    priv_key = Wallet.get_private_key()
    {:ok, signed_tx} = SignedTx.sign_tx(tx, priv_key)
    assert :error = Pool.add_transaction(signed_tx)
  end
end
