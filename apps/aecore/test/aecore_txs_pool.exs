defmodule AecoreTxsPoolTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool

  setup do
    Pool.start_link()
    []
  end

  test "add transaction to pool" do
    assert :ok = Pool.add_transaction(
      Aecore.Txs.Tx.create(Aecore.Keys.Worker.pubkey(), 5))
  end

  test "remove transaction from pool" do
    assert :ok = Pool.remove_transaction(Aecore.Txs.Tx.create(
      Aecore.Keys.Worker.pubkey(), 5))
  end

  test "get pool" do
    Pool.add_transaction(
      Aecore.Txs.Tx.create(Aecore.Keys.Worker.pubkey(), 5))
    tx_pool = Pool.get_pool()
    assert Enum.count(tx_pool) == 1
  end

end
