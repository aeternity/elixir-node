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
    GenServer.start_link(__MODULE__, :not_running, name: __MODULE__)
  end

  def init(:not_running) do
    {:ok, :not_running}
  end

  def start_miner() do
    GenServer.call(__MODULE__, :start_miner)
  end

  def stop_miner() do
    GenServer.call(__MODULE__, :stop_miner, :infinity)
  end

  def get_status() do
    GenServer.call(__MODULE__, :get_status, :infinity)
  end

  def handle_call(:start_miner, _from, :not_running) do
    schedule_work()
    {:reply, :running, :running}
  end

  def handle_call(:stop_miner, _from, :running) do
    {:reply, :will_stop, :not_running}
  end

  def handle_call(:get_status, _from, status) do
    {:reply, status, status}
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
    Chain.add_block(block)
  end

  def handle_info(:work, state) do
    if(state == :running) do
      mine_next_block([])
      schedule_work()

    end
    {:noreply, state}
  end

  defp schedule_work do
    Process.send_after(self(), :work, 1000)
  end

end
