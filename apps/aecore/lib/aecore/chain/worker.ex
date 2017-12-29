defmodule Aecore.Chain.Worker do
  @moduledoc """
  Module for working with chain
  """

  require Logger

  alias Aecore.Structures.Block
  alias Aecore.Chain.ChainState
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Chain.BlockValidation
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Difficulty

  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  def init(_) do
    genesis_block_hash = BlockValidation.block_header_hash(Block.genesis_block().header)
    genesis_block_map = %{genesis_block_hash => Block.genesis_block()}
    genesis_chain_state =
      ChainState.calculate_block_state(Block.genesis_block().txs, Block.genesis_block().header.height)
    chain_states = %{genesis_block_hash => genesis_chain_state}
    txs_index = calculate_block_acc_txs_info(Block.genesis_block())

    {:ok, %{blocks_map: genesis_block_map, chain_states: chain_states, txs_index: txs_index, top_hash: genesis_block_hash, top_height: 0}}
  end

  @spec top_block() :: Block.t
  def top_block() do
    GenServer.call(__MODULE__, :top_block)
  end

  @spec top_block_chain_state() :: tuple()
  def top_block_chain_state() do
    GenServer.call(__MODULE__, :top_block_chain_state)
  end

  @spec top_block_hash() :: binary
  def top_block_hash() do
    GenServer.call(__MODULE__, :top_block_hash)
  end

  @spec top_height() :: integer
  def top_height() do
    GenServer.call(__MODULE__, :top_height)
  end

  @spec get_block_by_hex_hash(term) :: Block.t
  def get_block_by_hex_hash(hash) do
    {:ok, decoded_hash} = Base.decode16(hash)
    GenServer.call(__MODULE__, {:get_block, decoded_hash})
  end

  @spec get_block(binary) :: Block.t
  def get_block(hash) do
    GenServer.call(__MODULE__, {:get_block, hash})
  end

  @spec has_block?(binary) :: true | false
  def has_block?(hash) do
    GenServer.call(__MODULE__, {:has_block, hash})
  end

  @spec get_blocks(binary, integer) :: list(Block.t)
  def get_blocks(start_block_hash, size) do
    Enum.reverse(get_blocks([], start_block_hash, size))
  end

  @spec add_block(Block.t) :: :ok | {:error, binary}
  def add_block(%Block{} = block) do
    prev_block = get_block(block.header.prev_hash) #TODO: catch error
    prev_block_chain_state = chain_state(block.header.prev_hash)
    new_block_state = ChainState.calculate_block_state(block.txs, prev_block.header.height)
    new_chain_state = ChainState.calculate_chain_state(new_block_state, prev_block_chain_state)
    new_chain_state_locked_amounts =
      ChainState.update_chain_state_locked(new_chain_state, prev_block.header.height + 1)

    blocks_for_difficulty_calculation = get_blocks(block.header.prev_hash, Difficulty.get_number_of_blocks())
    BlockValidation.validate_block!(block, prev_block, new_chain_state_locked_amounts, blocks_for_difficulty_calculation)
    add_validated_block(block, new_chain_state_locked_amounts)
  end

  @spec add_validated_block(Block.t, map) :: :ok
  defp add_validated_block(%Block{} = block, chain_state) do
    GenServer.call(__MODULE__, {:add_validated_block, block, chain_state})
  end

  @spec chain_state(binary) :: map
  def chain_state(block_hash) do
    GenServer.call(__MODULE__, {:chain_state, block_hash})
  end

  @spec txs_index() :: map
  def txs_index() do
    GenServer.call(__MODULE__, :txs_index)
  end

  def chain_state() do
    top_block_chain_state()
  end

  def longest_blocks_chain() do
    get_blocks(top_block_hash(), top_height() + 1)
  end

  ## Server side

  def handle_call(:current_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:top_block, _from, %{blocks_map: blocks_map, top_hash: top_hash} = state) do
    {:reply, blocks_map[top_hash], state}
  end

  def handle_call(:top_block_hash,  _from, %{top_hash: top_hash} = state) do
    {:reply, top_hash, state}
  end

  def handle_call(:top_block_chain_state, _from, %{chain_states: chain_states, top_hash: top_hash} = state) do
    {:reply, chain_states[top_hash], state}
  end

  def handle_call(:top_height, _from, %{top_height: top_height} = state) do
    {:reply, top_height, state}
  end

  def handle_call({:get_block, block_hash}, _from, %{blocks_map: blocks_map} = state) do
    block = blocks_map[block_hash]

    if block != nil do
      {:reply, block, state}
    else
      {:reply, {:error, "Block not found"}, state}
    end
  end

  def handle_call({:has_block, hash}, _from, %{blocks_map: blocks_map} = state) do
    has_block = Map.has_key?(blocks_map, hash)
    {:reply, has_block, state}
  end

  def handle_call({:add_validated_block, %Block{} = new_block, new_chain_state},
                  _from,
                  %{blocks_map: blocks_map, chain_states: chain_states,
                    txs_index: txs_index, top_height: top_height} = state) do
    new_block_txs_index = calculate_block_acc_txs_info(new_block)
    new_txs_index = update_txs_index(txs_index, new_block_txs_index)
    Enum.each(new_block.txs, fn(tx) -> Pool.remove_transaction(tx) end)
    new_block_hash = BlockValidation.block_header_hash(new_block.header)

    updated_blocks_map = Map.put(blocks_map, new_block_hash, new_block)
    updated_chain_states = Map.put(chain_states, new_block_hash, new_chain_state)

    total_tokens = ChainState.calculate_total_tokens(new_chain_state)
    Logger.info(fn ->
      "Added block ##{new_block.header.height} with hash #{Base.encode16(new_block_hash)}, total tokens: #{inspect(total_tokens)}"
    end)
    ## Store new block to disk
    Persistence.write_block_by_hash(new_block)
    state_update1 = %{state | blocks_map: updated_blocks_map,
                              chain_states: updated_chain_states,
                              txs_index: new_txs_index}
    if top_height < new_block.header.height do
      ## We send the block to others only if it extends the longest chain
      Peers.broadcast_block(new_block)
      {:reply, :ok, %{state_update1 | top_hash: new_block_hash,
                                      top_height: new_block.header.height}}
    else
      {:reply, :ok, state_update1}
    end
  end

  def handle_call({:chain_state, block_hash}, _from, %{chain_states: chain_states} = state) do
    {:reply, chain_states[block_hash], state}
  end

  def handle_call(:txs_index, _from, %{txs_index: txs_index} = state) do
    {:reply, txs_index, state}
  end

  defp calculate_block_acc_txs_info(block) do
    block_hash = BlockValidation.block_header_hash(block.header)
    accounts = for tx <- block.txs do
      [tx.data.from_acc, tx.data.to_acc]
    end
    accounts_unique = accounts |> List.flatten() |> Enum.uniq() |> List.delete(nil)
    for account <- accounts_unique, into: %{} do
      acc_txs = Enum.filter(block.txs, fn(tx) ->
          tx.data.from_acc == account || tx.data.to_acc == account
        end)
      tx_hashes = Enum.map(acc_txs, fn(tx) ->
          tx_bin = :erlang.term_to_binary(tx)
          :crypto.hash(:sha256, tx_bin)
        end)
      tx_tuples = Enum.map(tx_hashes, fn(hash) ->
          {block_hash, hash}
        end)
      {account, tx_tuples}
    end
  end

  defp update_txs_index(current_txs_index, new_block_txs_index) do
    Map.merge(current_txs_index, new_block_txs_index,
      fn(_, current_list, new_block_list) ->
        current_list ++ new_block_list
      end)
  end

  defp get_blocks(blocks_acc, next_block_hash, size) do
    if size > 0 do
      case(GenServer.call(__MODULE__, {:get_block, next_block_hash})) do
        {:error, _} -> blocks_acc
        block ->
          updated_block_acc = [block | blocks_acc]
          prev_block_hash = block.header.prev_hash
          next_size = size - 1

          get_blocks(updated_block_acc, prev_block_hash, next_size)
      end
    else
      blocks_acc
    end
  end
end
