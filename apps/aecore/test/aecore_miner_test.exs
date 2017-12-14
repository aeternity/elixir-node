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
    assert Chain.top_height() >= 1
    assert Chain.top_block().header.height >= 1
    assert length(Chain.longest_blocks_chain()) > 1
    top_block = Chain.top_block
    top_block_coinbase_tx = Enum.at(top_block.txs, 0)
    assert top_block_coinbase_tx.signature == nil
    assert top_block_coinbase_tx.data.from_acc == nil
    assert top_block_coinbase_tx.data.value <= Miner.coinbase_transaction_value()
    assert SignedTx.is_coinbase(top_block_coinbase_tx)
  end

end
