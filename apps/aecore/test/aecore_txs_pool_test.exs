defmodule AecoreTxsPoolTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys

  setup do
    Pool.start_link()
    []
  end

  test "add transaction, remove it and get pool" do
    {:ok, tx1} = Keys.sign_tx(elem(Keys.pubkey(), 1), 5)
    {:ok, tx2} = Keys.sign_tx(elem(Keys.pubkey(), 1), 5)
    assert :ok = Pool.add_transaction(tx1)
    assert :ok = Pool.add_transaction(tx2)
    assert :ok = Pool.remove_transaction(tx2)
    assert Enum.count(Pool.get_pool()) == 1
    Miner.resume()
    Miner.suspend()
    assert length(Chain.all_blocks) > 1
    assert Enum.count(Chain.latest_block.txs) == 2
    assert Enum.count(Pool.get_pool()) == 0
  end

end
