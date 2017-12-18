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
    Pool.start_link([])
    []
  end

  @tag timeout: 1_000_000_000
  test "add transaction, remove it and get pool" do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx1} = Keys.sign_tx(to_account, 5,
                              Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 10)
    {:ok, tx2} = Keys.sign_tx(to_account, 5,
                              Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 10)
    Miner.resume()
    Miner.suspend()
    assert :ok = Pool.add_transaction(tx1)
    assert :ok = Pool.add_transaction(tx2)
    assert :ok = Pool.remove_transaction(tx2)
    assert Enum.count(Pool.get_pool()) == 1
    Miner.resume()
    Miner.suspend()
    assert length(Chain.longest_blocks_chain()) > 1
    assert Enum.count(Chain.top_block().txs) == 2
    assert Enum.empty?(Pool.get_pool())
  end

  test "add negative transaction fail" do
    {:ok, to_account} = Keys.pubkey()
    {:ok, tx} = Keys.sign_tx(to_account, -5, Map.get(Chain.chain_state, to_account, %{nonce: 0}).nonce + 1, 10)
    assert :error = Pool.add_transaction(tx)
  end

end
