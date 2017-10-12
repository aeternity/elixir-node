defmodule AecoreTxsPoolTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain

  setup do
    Pool.start_link()
    []
  end

  test "add transaction to pool, mine and remove transaction from pool" do
    {:ok, pubkey} = Aecore.Keys.Worker.pubkey()
    assert :ok = Pool.add_transaction(Aecore.Txs.Tx.create(pubkey, 5))
    Miner.resume()
    Miner.suspend()
    assert length(Chain.all_blocks) > 0
    tx_pool = Pool.get_pool()
    assert Enum.count(tx_pool) == 0
  end

end
