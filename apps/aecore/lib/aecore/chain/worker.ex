defmodule Aecore.Chain.Worker do
  @moduledoc """
  Module for working with chain
  """

  alias Aecore.Block.Genesis
  alias Aecore.Structures.Block
  alias Aecore.Chain.ChainState

  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, {[Genesis.genesis_block()],
      ChainState.calculate_block_state(Genesis.genesis_block())},
      name: __MODULE__)
  end

  def init(initial_state) do
    {:ok, initial_state}
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

  def handle_call(:latest_block, _from, state) do
    [lb | _] = elem(state, 0)
    {:reply, lb, state}
  end

  def handle_call(:all_blocks, _from, state) do
    chain = elem(state, 0)
    {:reply, chain, state}
  end

  def handle_call({:add_block, %Block{} = b}, _from, state) do
    #TODO validations
    chain = elem(state, 0)
    chain_state = elem(state, 1)
    chain_state = ChainState.calculate_chain_state(chain_state, b)
    {:reply, :ok, {[b | chain], chain_state}}
  end

end
