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
  alias Aehttpserver.Web.Notify

  use GenServer
  use Bitwise

  @max_refs 30 #upper limit for number of blocks is 2^max_refs

  def start_link(_args) do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  def init(_) do
    genesis_block_hash = BlockValidation.block_header_hash(Block.genesis_block().header)
    genesis_chain_state = ChainState.calculate_and_validate_chain_state!(Block.genesis_block().txs, %{}, 0)
    blocks_map = %{genesis_block_hash => 
      %{block: Block.genesis_block(),
        chain_state: genesis_chain_state,
        refs: :array.new(0)}}
    txs_index = calculate_block_acc_txs_info(Block.genesis_block())

    {:ok, %{blocks_map: blocks_map, 
            txs_index: txs_index,
            top_hash: genesis_block_hash, 
            top_height: 0}}
  end

  @spec top_block() :: Block.t()
  def top_block() do
    GenServer.call(__MODULE__, :top_block_info).block
  end

  @spec top_block_chain_state() :: tuple()
  def top_block_chain_state() do
    GenServer.call(__MODULE__, :top_block_info).chain_state
  end

  @spec top_block_hash() :: binary()
  def top_block_hash() do
    GenServer.call(__MODULE__, :top_block_hash)
  end

  @spec top_height() :: integer()
  def top_height() do
    GenServer.call(__MODULE__, :top_height)
  end

  @spec get_block_by_hex_hash(term()) :: Block.t() | {:error, binary()}
  def get_block_by_hex_hash(hash) do
    {:ok, decoded_hash} = Base.decode16(hash)
    case GenServer.call(__MODULE__, {:get_block_info, decoded_hash}) do
      error = {:error, _} ->
        error
      data -> data.block
    end
  end

  @spec get_block(binary()) :: Block.t() | {:error, binary()}
  def get_block(hash) do
    case GenServer.call(__MODULE__, {:get_block_info, hash}) do
      error = {:error, _} ->
        error
      data -> data.block
    end
  end

  def get_block_by_height(height, chain_hash \\ nil) do
    get_block_info_by_height(height, chain_hash).block 
  end 
  
  @spec has_block?(binary()) :: boolean()
  def has_block?(hash) do
    GenServer.call(__MODULE__, {:has_block, hash})
  end

  @spec get_blocks(binary(), integer()) :: list(Block.t())
  def get_blocks(start_block_hash, count) do
    Enum.reverse(get_blocks([], start_block_hash, nil, count))
  end

  @spec get_blocks(binary(), binary(), integer()) :: list(Block.t())
  def get_blocks(start_block_hash, final_block_hash, count) do
    Enum.reverse(get_blocks([], start_block_hash, final_block_hash, count))
  end

  def longest_blocks_chain() do
    get_blocks(top_block_hash(), top_height() + 1)
  end
 
  def get_chain_state_by_height(height, chain_hash \\ nil) do
    get_block_info_by_height(height, chain_hash).chain_state
  end

  @spec chain_state(binary()) :: map()
  def chain_state(block_hash) do
    case GenServer.call(__MODULE__, {:get_block_info, block_hash}) do
      error = {:error, _} ->
        error
      data -> data.chain_state
    end
  end

  def chain_state() do
    top_block_chain_state()
  end

  @spec add_block(Block.t()) :: :ok | {:error, binary()}
  def add_block(%Block{} = block) do
    prev_block = get_block(block.header.prev_hash) #TODO: catch error
    prev_block_chain_state = chain_state(block.header.prev_hash)

    blocks_for_difficulty_calculation = get_blocks(block.header.prev_hash, Difficulty.get_number_of_blocks())
    new_chain_state = BlockValidation.calculate_and_validate_block!(
      block, prev_block, prev_block_chain_state, blocks_for_difficulty_calculation)
    add_validated_block(block, new_chain_state)
  end

  @spec add_validated_block(Block.t(), map()) :: :ok
  defp add_validated_block(%Block{} = block, chain_state) do
    GenServer.call(__MODULE__, {:add_validated_block, block, chain_state})
  end


  @spec txs_index() :: map()
  def txs_index() do
    GenServer.call(__MODULE__, :txs_index)
  end

  ## Server side

  def handle_call(:current_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:top_block_info, _from, %{blocks_map: blocks_map, top_hash: top_hash} = state) do
    {:reply, blocks_map[top_hash], state}
  end

  def handle_call(:top_block_hash,  _from, %{top_hash: top_hash} = state) do
    {:reply, top_hash, state}
  end

  def handle_call(:top_height, _from, %{top_height: top_height} = state) do
    {:reply, top_height, state}
  end

  def handle_call({:get_block_info, block_hash}, _from, %{blocks_map: blocks_map} = state) do
    block_info = blocks_map[block_hash]

    if block_info != nil do
      {:reply, block_info, state}
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
                  %{blocks_map: blocks_map, txs_index: txs_index, 
                    top_height: top_height} = state) do
    new_block_txs_index = calculate_block_acc_txs_info(new_block)
    new_txs_index = update_txs_index(txs_index, new_block_txs_index)
    new_block_hash = BlockValidation.block_header_hash(new_block.header)
    # refs_list is generated so it contains n-th prev blocks for n-s beeing a power of two. So for chain A<-B<-C<-D<-E<-F<-G<-H. H refs will be [G,F,D,A]. This allows for log n findning of block with given height.
    new_refs =
      Enum.reduce(0..@max_refs,
                  [new_block.header.prev_hash],
                  fn (i, [prev | _] = acc) ->
                    if :array.size(blocks_map[prev].refs) > i do
                      [:array.get(i, blocks_map[prev].refs) | acc]
                    else
                      acc
                    end
                  end)
      |> Enum.reverse
      |> :array.from_list
      |> :array.fix

    updated_blocks_map = Map.put(blocks_map, new_block_hash,
                                 %{block: new_block,
                                   chain_state: new_chain_state,
                                   refs: new_refs})
    total_tokens = ChainState.calculate_total_tokens(new_chain_state)
    Logger.info(fn ->
      "Added block ##{new_block.header.height} with hash #{Base.encode16(new_block_hash)}, total tokens: #{inspect(total_tokens)}"
    end)

    ## Store new block to disk
    Persistence.write_block_by_hash(new_block)
    state_update1 = %{state | blocks_map: updated_blocks_map,
                              txs_index: new_txs_index}
    if top_height < new_block.header.height do
      Enum.each(new_block.txs, fn(tx) -> Pool.remove_transaction(tx) end)
      ## We send the block to others only if it extends the longest chain
      Peers.broadcast_block(new_block)
      # Broadcasting notifications for new block added to chain and new mined transaction
      Notify.broadcast_new_block_added_to_chain_and_new_mined_tx(new_block)
      {:reply, :ok, %{state_update1 | top_hash: new_block_hash,
                                      top_height: new_block.header.height}}
    else
      {:reply, :ok, state_update1}
    end
  end

  def handle_call(:txs_index, _from, %{txs_index: txs_index} = state) do
    {:reply, txs_index, state}
  end

  def handle_call(:blocks_map, _from, %{blocks_map: blocks_map} = state) do
    {:reply, blocks_map, state}
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

  defp get_blocks(blocks_acc, next_block_hash, final_block_hash, count) do
    if next_block_hash != final_block_hash && count > 0 do
      case(GenServer.call(__MODULE__, {:get_block_info, next_block_hash})) do
        {:error, _} -> blocks_acc
        block_info ->
          block = block_info.block
          updated_blocks_acc = [block | blocks_acc]
          prev_block_hash = block.header.prev_hash
          next_count = count - 1

          get_blocks(updated_blocks_acc, prev_block_hash, final_block_hash, next_count)
      end
    else
      blocks_acc
    end
  end

  defp get_block_info_by_height(height, chain_hash \\ nil) do
    begin_hash = if chain_hash == nil do top_block_hash() else chain_hash end
    blocks_map = GenServer.call(__MODULE__, :blocks_map)
    n = blocks_map[begin_hash].block.header.height - height
    if n < 0 do
      {:error, "Height higher then chain_hash height"}
    else
      blocks_map[get_nth_prev_hash(n, 0, begin_hash, blocks_map)]
    end
  end
  
  defp get_nth_prev_hash(0, _i, hash, blocks_map) do
    hash
  end
  defp get_nth_prev_hash(n, i, hash, blocks_map) do
    if (n &&& (1 <<< i)) != 0 do
      get_nth_prev_hash(n - (1 <<< i),
                        i + 1,
                        :array.get(i, blocks_map[hash].refs),
                        blocks_map)
    else
      get_nth_prev_hash(n, i + 1, hash, blocks_map) 
    end
  end

end
