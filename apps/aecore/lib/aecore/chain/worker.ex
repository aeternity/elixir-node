defmodule Aecore.Chain.Worker do
  @moduledoc """
  Module for working with chain
  """

  require Logger

  alias Aecore.Structures.Block
  alias Aecore.Chain.ChainState
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Utils.Blockchain.Difficulty

  use GenServer

  def start_link do
    GenServer.start_link(
      __MODULE__,
      {[Block.genesis_block()], ChainState.calculate_block_state(Block.genesis_block().txs)},
      name: __MODULE__
    )
  end

  def init(initial_state) do
    {:ok, initial_state}
  end

  @spec latest_block() :: %Block{}
  def latest_block() do
    GenServer.call(__MODULE__, :latest_block)
  end

  @spec get_prior_blocks_for_validity_check() :: tuple()
  def get_prior_blocks_for_validity_check() do
    GenServer.call(__MODULE__, :get_prior_blocks_for_validity_check)
  end

  @spec get_block_by_hash(term()) :: %Block{}
  def get_block_by_hash(hash) do
    GenServer.call(__MODULE__, {:get_block_by_hash, hash})
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

  @spec get_blocks_for_difficulty_calculation() :: list()
  def get_blocks_for_difficulty_calculation() do
    GenServer.call(__MODULE__, :get_blocks_for_difficulty_calculation)
  end

  def handle_call(:latest_block, _from, state) do
    [lb | _] = elem(state, 0)
    {:reply, lb, state}
  end

  def handle_call(:get_prior_blocks_for_validity_check, _from, state) do
    chain = elem(state, 0)

    if length(chain) == 1 do
      [lb | _] = chain
      {:reply, {lb, nil}, state}
    else
      [lb, prev | _] = chain
      {:reply, {lb, prev}, state}
    end
  end

  def handle_call({:get_block_by_hash, hash}, _from, state) do
    block = Enum.find(elem(state, 0), fn(block) ->
      block.header
      |> BlockValidation.block_header_hash()
      |> Base.encode16() == hash end)
    {:reply, block, state}
  end

  def handle_call(:all_blocks, _from, state) do
    chain = elem(state, 0)
    {:reply, chain, state}
  end

  def handle_call({:add_block, %Block{} = b}, _from, state) do
    {chain, prev_chain_state} = state
    [prior_block | _] = chain
    new_block_state = ChainState.calculate_block_state(b.txs)
    new_chain_state = ChainState.calculate_chain_state(new_block_state, prev_chain_state)

    try do
      BlockValidation.validate_block!(b, prior_block,
      new_chain_state)
      total_tokens = ChainState.calculate_total_tokens(new_chain_state)
      Logger.info(fn ->
        "Added block ##{b.header.height} with hash #{b.header
        |> BlockValidation.block_header_hash()
        |> Base.encode16()}, total tokens: #{total_tokens}"
      end)
      {:reply, :ok, {[b | chain], new_chain_state}}
    catch
      {:error, message} ->
        Logger.error(fn ->
          "Failed to add block: #{message}"
        end)
      {:reply, :error, state}
    end
  end

  def handle_call(:chain_state, _from, state) do
    chain_state = elem(state, 1)
    {:reply, chain_state, state}
  end

  def handle_call(:get_blocks_for_difficulty_calculation, _from, state) do
    chain = elem(state, 0)
    number_of_blocks = Difficulty.get_number_of_blocks()
    blocks_for_difficulty_calculation = Enum.take(chain, number_of_blocks)
    {:reply, blocks_for_difficulty_calculation, state}
  end
end
