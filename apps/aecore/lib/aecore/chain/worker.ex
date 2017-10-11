defmodule Aecore.Chain.Worker do
  @moduledoc """
  Module for working with chain
  """

  alias Aecore.Block.Genesis
  alias Aecore.Structures.Block
  alias Aecore.Chain.ChainState
  alias Aecore.Utils.Blockchain.BlockValidation

  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, {[Genesis.genesis_block()],
      ChainState.calculate_block_state(Genesis.genesis_block().txs)},
      name: __MODULE__)
  end

  def init(initial_state) do
    {:ok, initial_state}
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

  @spec chain_state() :: map()
  def chain_state() do
   GenServer.call(__MODULE__, :chain_state)
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
    {chain, prev_chain_state} = state
    [prior_block | _] = chain
    if(:ok = BlockValidation.validate_block!(b, prior_block,
             prev_chain_state)) do
      new_block_chain_state = ChainState.calculate_block_state(b.txs)
      new_chain_state =
        ChainState.calculate_chain_state(new_block_chain_state,
        prev_chain_state)
      {:reply, :ok, {[b | chain], new_chain_state}}
    else
      {:reply, {:error, "invalid block"}, state}
    end
  end

  def handle_call(:chain_state, _from, state) do
   chain_state = elem(state, 1)
   {:reply, chain_state, state}
  end

end
