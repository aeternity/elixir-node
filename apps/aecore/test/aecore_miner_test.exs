defmodule MinerTest do
  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner

  setup do
    on_exit(fn ->
      Persistence.delete_all_blocks()
      :ok
    end)
  end

  @tag timeout: 20_000
  @tag :miner
  test "mine_next_block", setup do
    Miner.mine_sync_block_to_chain()
    assert Chain.top_height() >= 1
    assert Chain.top_block().header.height >= 1
    assert length(Chain.longest_blocks_chain()) > 1
    top_block = Chain.top_block()
    top_block_coinbase_tx = Enum.at(top_block.txs, 0)
    assert top_block_coinbase_tx.signature == nil
    assert top_block_coinbase_tx.data.from_acc == nil
    assert top_block_coinbase_tx.data.payload.value <= Miner.coinbase_transaction_value()
    assert SignedTx.is_coinbase?(top_block_coinbase_tx)
  end
end
