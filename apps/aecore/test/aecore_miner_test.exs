defmodule MinerTest do
  use ExUnit.Case

  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner

  @tag timeout: 100_000_000
  test "mine_next_block" do
    Miner.start_link([])
    Miner.resume()
    Miner.suspend()
    assert length(Chain.all_blocks) > 1
    latest_block = Chain.latest_block
    latest_block_coinbase_tx = Enum.at(latest_block.txs, 0)
    assert latest_block_coinbase_tx.signature == nil
    assert latest_block_coinbase_tx.data.from_acc == nil
    assert latest_block_coinbase_tx.data.value <= Miner.coinbase_transaction_value()
    assert SignedTx.is_coinbase(latest_block_coinbase_tx)
  end

end
