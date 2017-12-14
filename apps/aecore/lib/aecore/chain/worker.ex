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
    genesis_chain_state = ChainState.calculate_block_state(Block.genesis_block().txs)
    chain_states = %{genesis_block_hash => genesis_chain_state}
    txs_index = calculate_block_acc_txs_info(Block.genesis_block())

    {:ok, %{blocks_map: genesis_block_map, chain_states: chain_states, txs_index: txs_index}}
  end

  @spec latest_block() :: %Block{}
  def latest_block() do
    latest_block_hashes = get_latest_block_chain_state() |> Map.keys()
    latest_block_hash = case(length(latest_block_hashes)) do
      1 -> List.first(latest_block_hashes)
      _ -> throw({:error, "multiple or none latest block hashes"})
    end

    get_block(latest_block_hash)
  end

  @spec get_latest_block_chain_state() :: tuple()
  def get_latest_block_chain_state() do
    GenServer.call(__MODULE__, :get_latest_block_chain_state)
  end

  @spec get_block_by_hex_hash(term()) :: %Block{}
  def get_block_by_hex_hash(hash) do
    GenServer.call(__MODULE__, {:get_block, Base.decode16(hash)})
  end

  @spec get_block(binary()) :: %Block{}
  def get_block(hash) do
    GenServer.call(__MODULE__, {:get_block, hash})
  end

  @spec has_block?(term()) :: true | false
  def has_block?(hash) do
    GenServer.call(__MODULE__, {:has_block, hash})
  end

  @spec get_blocks(binary(), integer()) :: :ok
  def get_blocks(start_block_hash, size) do
    Enum.reverse(get_blocks([], start_block_hash, size))
  end

  @spec add_block(%Block{}) :: :ok
  def add_block(%Block{} = block) do
    latest_block = latest_block()

    prev_block_chain_state = chain_state()
    new_block_state = ChainState.calculate_block_state(block.txs)
    new_chain_state = ChainState.calculate_chain_state(new_block_state, prev_block_chain_state)

    latest_header_hash = BlockValidation.block_header_hash(latest_block.header)

    blocks_for_difficulty_calculation = get_blocks(latest_header_hash, Difficulty.get_number_of_blocks())
    BlockValidation.validate_block!(block, latest_block, new_chain_state, blocks_for_difficulty_calculation)
    add_validated_block(block)
  end

  @spec add_validated_block(%Block{}) :: :ok
  defp add_validated_block(%Block{} = block) do
    GenServer.call(__MODULE__, {:add_validated_block, block})
  end

  @spec chain_state(binary()) :: map()
  def chain_state(latest_block_hash) do
    GenServer.call(__MODULE__, {:chain_state, latest_block_hash})
  end

  @spec txs_index() :: map()
  def txs_index() do
    GenServer.call(__MODULE__, :txs_index)
  end

  def chain_state() do
    latest_block = latest_block()
    latest_block_hash = BlockValidation.block_header_hash(latest_block.header)
    chain_state(latest_block_hash)
  end

  def all_blocks() do
    latest_block_obj = latest_block()
    latest_block_hash = BlockValidation.block_header_hash(latest_block_obj.header)
    get_blocks(latest_block_hash, latest_block_obj.header.height + 1)
  end

  ## Server side

  def handle_call(:get_current_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:get_latest_block_chain_state, _from, %{current_chain_state: current_chain_state} = state) do
    {:reply, current_chain_state, state}
  end

  def handle_call({:get_block, block_hash}, _from, %{blocks_map: blocks_map} = state) do
    block = blocks_map[block_hash]

    if block != nil do
      {:reply, block, state}
    else
      {:reply, {:error, "Block not found"}, state}
    end
  end

  def handle_call({:has_block, hex_hash}, _from, %{blocks_map: blocks_map} = state) do
    has_block =
      case Base.decode16(hex_hash) do
        {:ok, decoded_hash} ->
          Map.has_key?(blocks_map, decoded_hash)
        :error ->
          false
      end

    {:reply, has_block, state}
  end

  def handle_call({:add_validated_block, %Block{} = block}, _from, 
                  %{blocks_map: blocks_map, chain_states: chain_states, txs_index: txs_indes} = state) do
    prev_block_chain_state = chain_states[block.header.prev_hash]
    new_block_state = ChainState.calculate_block_state(block.txs)
    new_chain_state = ChainState.calculate_chain_state(new_block_state, prev_block_chain_state)

    new_block_txs_index = calculate_block_acc_txs_info(block)
    new_txs_index = update_txs_index(txs_index, new_block_txs_index)
    try do
      Enum.each(block.txs, fn(tx) -> Pool.remove_transaction(tx) end)

      block_hash = BlockValidation.block_header_hash(block.header)
      updated_blocks_map = Map.put(blocks_map, block_hash, block)
      has_prev_block = Map.has_key?(chain_states, block.header.prev_hash) ##TODO: we assume this is true on first line

      updated_chain_states = Map.put(chain_states, block_hash, new_chain_state)

      total_tokens = ChainState.calculate_total_tokens(new_chain_state)

      Logger.info(fn ->
        "Added block ##{block.header.height} with hash #{block.header
        |> BlockValidation.block_header_hash()
        |> Base.encode16()}, total tokens: #{total_tokens}"
      end)

      ## Store latest block to disk
      Persistence.write_block_by_hash(block)

      ## Block was validated, now we can send it to other peers
      Peers.broadcast_block(block)

      {:reply, :ok, %{blocks_map: updated_blocks_map, chain_states: updated_chain_states, txs_index: new_txs_index}}
    catch
      {:error, message} ->
        Logger.error(fn ->
          "Failed to add block: #{message}"
        end)
      {:reply, :error, state}
    end
  end

  def handle_call({:chain_state, block_hash}, _from, %{chain_states: chain_states} = state) do
    {:reply, chain_states[block_hash], state}
  end

  def handle_call(:txs_index, _from, %{txs_index: txs_index} = state) do
    {:reply, txs_index, state}
  end

  def terminate(_, state) do
    Persistence.store_state(state)
    Logger.warn("Terminting, state was stored on disk ...")

  end

  defp calculate_block_acc_txs_info(block) do
    block_hash = BlockValidation.block_header_hash(block.header)
    accounts = for tx <- block.txs do
      [tx.data.from_acc, tx.data.to_acc]
    end
    accounts = accounts |> List.flatten() |> Enum.uniq() |> List.delete(nil)
    for account <- accounts, into: %{} do
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
    cond do
      size > 0 ->
        case(GenServer.call(__MODULE__, {:get_block, next_block_hash})) do
          {:error, _} -> blocks_acc
          block ->
            updated_block_acc = [block | blocks_acc]
            prev_block_hash = block.header.prev_hash
            next_size = size - 1

            get_blocks(updated_block_acc, prev_block_hash, next_size)
        end
      true ->
        blocks_acc
    end
  end
end
