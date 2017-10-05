defmodule Aecore.Miner.Worker do
  @moduledoc """
  Module for the miner
  """

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Block.Genesis
  alias Aecore.Structures.Block
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Utils.Blockchain.Difficulty
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Block.Headers
  alias Aecore.Block.Blocks
  alias Aecore.Pow.Hashcash

  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    schedule_work()
    {:ok, []}
  end

  @spec mine_next_block(list()) :: :ok
  def mine_next_block(txs) do
    chain = Chain.all_blocks()
    difficulty = Difficulty.calculate_next_difficulty(chain)
    valid_txs = BlockValidation.filter_invalid_transactions(txs)
    latest_block = if(length(chain) == 1) do
      [latest_block | _] = chain
      latest_block
    else
      [latest_block, previous_block | _] = chain
      BlockValidation.validate_block!(latest_block, previous_block)
      latest_block
    end
    root_hash = BlockValidation.calculate_root_hash(valid_txs)
    latest_block_hash = BlockValidation.block_header_hash(latest_block)
    block_header = Headers.new(latest_block.header.height + 1, latest_block_hash, root_hash, difficulty, 0, 1)
    {:ok, mined_header} = Hashcash.generate(block_header)
    {:ok, block} = Blocks.new(mined_header, valid_txs)
    IO.inspect(block)
    Chain.add_block(block)
  end

  def handle_info(:work, state) do
    mine_next_block([])
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work do
    Process.send_after(self(), :work, 0)
  end

end
