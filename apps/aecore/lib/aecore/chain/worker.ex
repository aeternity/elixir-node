defmodule Aecore.Chain.Worker do
  @moduledoc """
  Module for working with chain
  """

  alias Aecore.Block.Genesis
  alias Aecore.Structures.Block
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Utils.Blockchain.Difficulty
  alias Aecore.Structures.TxData
  alias Aecore.Block.Headers
  alias Aecore.Block.Blocks
  alias Aecore.Pow.Hashcash

  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [Genesis.genesis_block()], name: __MODULE__)
  end

  def init([%Block{}] = initial_chain) do
    {:ok, initial_chain}
  end

  def latest_block() do
    GenServer.call(__MODULE__, :latest_block)
  end

  def all_blocks() do
    GenServer.call(__MODULE__, :all_blocks)
  end

  def add_block(%Block{} = b) do
    GenServer.call(__MODULE__, {:add_block, b})
  end

  def mine_next_block(txs) do
    GenServer.call(__MODULE__, {:txs, txs}, :infinity)
  end

  def handle_call(:latest_block, _from, chain) do
    [lb | _] = chain
    {:reply, lb, chain}
  end

  def handle_call(:all_blocks, _from, chain) do
    {:reply, chain, chain}
  end

  def handle_call({:add_block, %Block{} = b}, _from, chain) do
    #TODO validations
    {:reply, :ok, [b | chain]}
  end

  def miner_1() do
    mine_next_block([])
    miner_2
  end

  def miner_2() do
    mine_next_block([])
    miner_1()
  end

  def handle_call({:txs, txs}, _from, chain) do
    difficulty = Difficulty.calculate_next_difficulty(chain)
    [latest_block | _] = chain
    root_hash = BlockValidation.calculate_root_hash(txs)
    block_header = Headers.new(latest_block.header.height + 1, latest_block.header.prev_hash, root_hash, difficulty, 0, 1)
    {:ok, mined_header} = Hashcash.generate(block_header)
    {:ok, block} = Blocks.new(mined_header, txs)
    IO.inspect(block)
    {:reply, :ok, [block | chain]}
  end

end
