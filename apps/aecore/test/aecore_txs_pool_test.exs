defmodule AecoreTxsPoolTest do
  @moduledoc """
  Unit test for the pool worker module
  """
  use ExUnit.Case

  alias Aecore.Structures.SignedTx
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Keys.Worker, as: Keys

  setup do
    Pool.start_link()
    []
  end

  test "add transaction, remove it and get pool" do
    {:ok, tx1} = Keys.sign_tx(Keys.pubkey(), 5)
    {:ok, tx2} = Keys.sign_tx(Keys.pubkey(), 5)
    assert :ok = Pool.add_transaction(tx1)
    assert :ok = Pool.add_transaction(tx1)
    assert :ok = Pool.remove_transaction(tx2)
    tx_pool = Pool.get_pool()
    assert Enum.count(tx_pool) == 1
  end

end
