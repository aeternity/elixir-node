defmodule Aecore.Peers.Sync do

  @peers_target_count Application.get_env(:aecore, :peers)[:peers_target_count]

  alias Aecore.Peers.Worker, as: Peers
  alias Aehttpclient.Client, as: HttpClient
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Chain.BlockValidation
  alias Aeutil.Serialization

  use GenServer

  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def get_state() do
    GenServer.call(__MODULE__, :get_state)
  end

  @spec add_block_to_state(binary(), term()) :: :ok
  def add_block_to_state(block_hash, block) do
    GenServer.call(__MODULE__, {:add_block_to_state, block_hash, block})
  end

  @spec ask_peers_for_unknown_blocks(map()) :: :ok
  def ask_peers_for_unknown_blocks(peers) do
    GenServer.call(__MODULE__, {:ask_peers_for_unknown_blocks, peers})
  end

  @spec add_valid_peer_blocks_to_chain() :: :ok
  def add_valid_peer_blocks_to_chain() do
    GenServer.call(__MODULE__, :add_valid_peer_blocks_to_chain)
  end

  def add_unknown_peer_pool_txs(peers) do
    peer_uris = peers |> Map.values() |> Enum.map(fn(%{uri: uri}) -> uri end)
    Enum.each(peer_uris, fn(peer) ->
      case HttpClient.get_pool_txs(peer) do
        {:ok, deserialized_pool_txs} ->
          Enum.each(deserialized_pool_txs,
            fn(tx) -> Pool.add_transaction(tx) end)
        :error ->
          Logger.error("Couldn't get pool from peer")
      end
    end)
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:add_block_to_state, block_hash, block}, _from, state) do
    updated_state =
      case Chain.has_block?(block_hash) do
        true ->
          state
        false ->
          try do
            BlockValidation.single_validate_block(block)
            Map.put(state, block_hash, block)
          catch
            {:error, message} ->
              Logger.error(fn -> "Can't add block to Sync state; #{message}" end)
              state
          end
      end

    {:reply, :ok, updated_state}
  end

  def handle_call({:ask_peers_for_unknown_blocks, peers}, _from, state) do
    state = Enum.reduce(peers, state, fn ({_, %{uri: uri, latest_block: top_block_hash}}, acc) ->
        {:ok, top_hash_decoded} = Base.decode16(top_block_hash)
        Map.merge(acc, check_peer_block(uri, top_hash_decoded, %{}))
      end)

    {:reply, :ok, state}
  end

  def handle_call(:add_valid_peer_blocks_to_chain, _from, state) do
    filtered_state =
      Enum.reduce(state, state, fn({_, block}, acc) ->
          built_chain = build_chain(acc, block, [])
          add_built_chain(built_chain, acc)
      end)

    {:reply, :ok, filtered_state}
  end

  #To make sure no peer is more popular in network then others,
  #we remove one peer at random if we have at least target_count of peers.
  @spec introduce_variety :: :ok
  def introduce_variety do
    peers_count = map_size(Peers.all_peers())
    if peers_count >= @peers_target_count do
      random_peer = Enum.random(Map.keys(Peers.all_peers()))
      Logger.info(fn -> "Removing #{random_peer} to introduce variety" end)
      Peers.remove_peer(random_peer)
      :ok
    else
      :ok
    end
  end

  #If our peer count is lower then @peers_target_count,
  #we request peers list from all known peers and choose at random
  #min(peers_we_need_to_have_target_count, peers_we_currently_have)
  #new peers to add.
  @spec refill :: :ok | {:error, term()}
  def refill do
    peers_count = map_size(Peers.all_peers())
    cond do
      peers_count == 0 ->
        {:error, "No peers"}
      peers_count < @peers_target_count ->
        all_peers =
          Peers.all_peers()
            |> Map.values()
            |> Enum.map(fn(%{uri: uri}) -> uri end)
        new_count = get_newpeers_and_add(all_peers)
        if new_count > 0 do
          Logger.info(fn -> "Aquired #{new_count} new peers" end)
          :ok
        else
          Logger.debug(fn -> "No new peers added when trying to refill peers" end)
          {:error, "No new peers added"}
        end
      true ->
        :ok
    end
  end

  defp get_newpeers_and_add(known) do
    known_count = length(known)
    known_set = MapSet.new(known)
    number_of_peers_to_add = Enum.min([@peers_target_count - known_count, known_count])
    known
    |> Enum.shuffle
    |> Enum.take(@peers_target_count - known_count)
    |> Enum.reduce([], fn(peer, acc) ->
      case (HttpClient.get_peers(peer)) do
        {:ok, list} ->
          Enum.concat(acc, Enum.map(Map.values(list),
                                    fn(%{"uri" => uri}) -> uri end))
        {:error, message} ->
          Logger.error(fn -> "Couldn't get peers from #{peer}: #{message}" end)
          acc
      end
    end)
    |> Enum.reduce([], fn(peer, acc) ->
      if MapSet.member?(known_set, peer) do
        acc
      else
        [peer | acc]
      end
    end)
    |> Enum.shuffle
    |> Enum.reduce(0, fn(peer, acc) ->
      #if we have successfully added less then number_of_peers_to_add peers then try to add another one
      if acc < number_of_peers_to_add do
        case Peers.add_peer(peer) do
          :ok ->
            acc + 1
          _ ->
            acc
        end
      else
        acc
      end
    end)
  end

  # Builds a chain, starting from the given block,
  # until we reach a block, of which the previous block is the highest in our chain
  # (that means we can add this chain to ours)
  defp build_chain(state, block, chain) do
    has_parent_block_in_state = Map.has_key?(state, block.header.prev_hash)
    has_parent_in_chain = Chain.has_block?(block.header.prev_hash)
    cond do
      has_parent_block_in_state ->
        build_chain(state, state[block.header.prev_hash], [block | chain])
      has_parent_in_chain ->
        [block | chain]
      true ->
        []
    end
  end

  # Adds the given chain to the local chain and
  # deletes the blocks we added from the state
  defp add_built_chain(chain, state) do
    Enum.reduce(chain, state, fn (block, acc) ->
        case Chain.add_block(block) do
          :ok ->
            Map.delete(acc, BlockValidation.block_header_hash(block.header))
          :error ->
            acc
        end
      end)
  end

  # Gets all unknown blocks, starting from the given one
  defp check_peer_block(peer_uri, block_hash, state) do
    case Chain.has_block?(block_hash) do
      false ->
        case(HttpClient.get_block({peer_uri, block_hash})) do
          {:ok, deserialized_block} ->
            try do
              BlockValidation.single_validate_block(deserialized_block)
              peer_block_hash =
                BlockValidation.block_header_hash(deserialized_block.header)

              if(block_hash == peer_block_hash) do
                check_peer_block(peer_uri, deserialized_block.header.prev_hash,
                  Map.put(state, peer_block_hash, deserialized_block))
              else
                state
              end
            catch
              {:error, _} ->
                state
            end
          :error ->
            state
        end
      true ->
        state
    end
  end
end
