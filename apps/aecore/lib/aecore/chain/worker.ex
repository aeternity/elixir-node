defmodule Aecore.Chain.Worker do
  @moduledoc """
  Module for working with chain
  """

  alias Aecore.Block.Genesis
  alias Aecore.Structures.Block
  alias Aecore.Utils.Blockchain.BlockValidation

  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [Genesis.genesis_block()], name: __MODULE__)
  end

  def init([%Block{}] = initial_chain) do
    {:ok, initial_chain}
  end

  @spec latest_block() :: %Block{}
  def latest_block() do
    GenServer.call(__MODULE__, :latest_block)
  end

  @spec all_blocks() :: list()
  def all_blocks() do
    GenServer.call(__MODULE__, :all_blocks)
  end

  @spec add_block(%Block{}) :: :ok
  def add_block(%Block{} = b) do
    GenServer.call(__MODULE__, {:add_block, b})
  end

  def handle_call(:latest_block, _from, chain) do
    [lb | _] = chain
    {:reply, lb, chain}
  end

  def handle_call(:all_blocks, _from, chain) do
    {:reply, chain, chain}
  end

  def handle_call({:add_block, %Block{} = b}, _from, chain) do
    [latest_block | _] = chain
    if(:ok = BlockValidation.validate_block!(b, latest_block)) do
      {:reply, :ok, [b | chain]}
    else
      {:reply, {:error, "invalid block"}, chain}
    end
  end

end
