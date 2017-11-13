defmodule Aecore.Peers.Sync do

  @check_time 60_000
  @peers_target_count Application.get_env(:aecore, :peers)[:peers_target_count]

  alias Aecore.Peers.Worker, as: Peers
  alias Aehttpclient.Client, as: HttpClient

  use GenServer

  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    Process.send_after(self(), :work, 5_000)
    {:ok, state}
  end

  @spec add_block_to_state(binary(), term()) :: :ok
  def add_block_to_state(block_hash, peer) do
    GenServer.call(__MODULE__, {:add_block_to_state, block_hash, peer})
  end

  @spec ask_peers_for_unknown_blocks() :: :ok
  def ask_peers_for_unknown_blocks() do
    GenServer.call(__MODULE__, :ask_peers_for_unknown_blocks)
  end

  @spec update_statuses() :: :ok
  def update_statuses() do
    GenServer.call(__MODULE__, :update_statuses)
  end

  @spec single_validate_all_blocks() :: :ok
  def single_validate_all_blocks() do
    GenServer.call(__MODULE__, :single_validate_all_blocks)
  end

  @spec add_valid_peer_blocks_to_chain() :: :ok
  def add_valid_peer_blocks_to_chain() do
    GenServer.call(__MODULE__, :add_valid_peer_blocks_to_chain)
  end

  def handle_call({:add_block_to_state, block_hash, peer}, _from, state) do
    updated_state = Map.put(state, block_hash, %{peer: peer, status: :bad})
    {:reply, :ok, updated_state}
  end

  def handle_call(:ask_peers_for_unknown_blocks, _from, state) do
    all_peers = Peers.all_peers()
    state = Enum.reduce(all_peers, state, fn ({uri, latest_block_hash}, acc) ->
        Map.merge(acc, check_peer_block(uri, latest_block_hash, %{}))
      end)

    {:reply, :ok, state}
  end

  def handle_call(:update_statuses, _from, state) do
    updated_state = for {block_hash, %{peer: peer, status: status}} <- state, into: %{} do
      case Chain.get_block_by_hex_hash(block_hash) do
        {:error, _} ->
          {block_hash, %{peer: peer, status: status}}
        block
         ->
          must_be_updated = status == :bad && Map.has_key?(state, block.header.prev_hash)
          case must_be_updated do
            true ->
              {block_hash, %{peer: peer, status: :good}}
            false ->
              {block_hash, %{peer: peer, status: status}}
          end
      end
    end

    {:reply, :ok, updated_state}
  end

  def handle_call(:single_validate_all_blocks, _from ,state) do
    updated_state = single_validate_all_blocks(state)

    {:reply, :ok, updated_state}
  end

  def handle_call(:add_valid_peer_blocks_to_chain, _from, state) do
    updated_state = single_validate_all_blocks(state)

    filtered_state = Enum.reduce(updated_state, updated_state, fn({block_hash, %{peer: peer}}, acc) ->
          built_chain = build_chain(acc, {block_hash, peer}, [])
          add_built_chain(built_chain)
          remove_added_blocks_from_state(acc)
      end)

    {:reply, :ok, filtered_state}
  end

  def handle_info(:work, state) do
    check_peers()
    introduce_variety()
    refill()
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, @check_time)
  end

  defp check_peers do
    Peers.check_peers()
  end

  #To make sure no peer is more popular in network then others,
  #we remove one peer at random if we have at least target_count of peers.
  @spec introduce_variety :: :ok
  defp introduce_variety do
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
  defp refill do
    peers_count = map_size(Peers.all_peers())
    cond do
      peers_count == 0 ->
        Logger.error(fn -> "No peers" end)
        {:error, "No peers"}
      peers_count < @peers_target_count ->
        all_peers = Map.keys(Peers.all_peers())
        new_count = get_newpeers_and_add(all_peers)
        if new_count > 0 do
          Logger.info(fn -> "Aquired #{new_count} new peers" end)
          :ok
        else
          Logger.error(fn -> "No new peers added when trying to refill peers" end)
          {:error, "No new peers added"}
        end
      true ->
        :ok
    end
  end

  defp get_newpeers_and_add(known) do
    known_count = length(known)
    known_set = MapSet.new(known)
    known
    |> Enum.shuffle
    |> Enum.take(@peers_target_count - known_count)
    |> Enum.reduce([], fn(peer, acc) ->
      case (HttpClient.get_peers(peer)) do
        {:ok, list} -> Enum.concat(list, acc)
        :error -> acc
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
    |> Enum.take(Enum.min([@peers_target_count - known_count, known_count]))
    |> Enum.reduce(0, fn(peer, acc) ->
      case Peers.add_peer(peer) do
        :ok -> acc+1
        _ -> acc
      end
    end)
  end

  defp build_chain(state, {block_hash, peer}, chain) do
    case(HttpClient.get_block({peer, Base.encode16(block_hash)})) do
      {:ok, peer_block} ->
        deserialized_block = Serialization.block(peer_block, :deserialize)
        has_parent_block_in_state = Map.has_key?(state, deserialized_block.header.prev_hash)
        has_parent_in_chain =
          deserialized_block.header.prev_hash == BlockValidation.block_header_hash(Chain.latest_block().header)
        cond do
          has_parent_block_in_state ->
            build_chain(state, {deserialized_block.header.prev_hash, peer}, [deserialized_block | chain])
          has_parent_in_chain ->
            [deserialized_block | chain]
          true ->
            []
        end
      :error ->
        Logger.info(fn -> "Couldn't get block #{block_hash} from #{peer}" end)
    end
  end

  defp add_built_chain(chain) do
    Enum.each(chain, fn(block) ->
        Chain.add_block(block)
      end)
  end

  defp remove_added_blocks_from_state(state) do
    state_with_removed_blocks = Enum.filter(state, fn {block_hash, _} ->
        case Chain.get_block(block_hash) do
          {:error, _} ->
            true
          _ ->
            false
        end
      end)

    List.foldl(state_with_removed_blocks, %{}, fn({block_hash, block_data}, acc) ->
        Map.put(acc, block_hash, block_data)
      end)
  end

  defp check_peer_block(peer_uri, block_hash, blocks_with_status) do
    case Chain.get_block_by_hex_hash(block_hash) do
      {:error, _} ->
        case(HttpClient.get_block({peer_uri, Base.encode16(block_hash)})) do
          {:ok, peer_block} ->
            deserialized_block = Serialization.block(peer_block, :deserialize)
            peer_block_hash =
              BlockValidation.block_header_hash(deserialized_block.header)
            status =
              case(HttpClient.get_block({peer_uri, Base.encode16(peer_block_hash)})) do
                {:ok, _peer_block_parent} ->
                  :good
                :error ->
                  :bad
              end

            check_peer_block(peer_uri, peer_block.header.prev_hash,
              Map.put(blocks_with_status,
               peer_block_hash, %{peer: peer_uri, status: status}))
          :error ->
            blocks_with_status
        end
      _ ->
        blocks_with_status
    end
  end

  defp single_validate_all_blocks(state) do
    filtered_blocks_list = Enum.filter(state, fn{block_hash, %{peer: peer}} ->
        block_hash_hex = Base.encode16(block_hash)
        case(HttpClient.get_block({peer, block_hash_hex})) do
          {:ok, peer_block} ->
            try do
              deserialized_block = Serialization.block(peer_block, :deserialize)
              BlockValidation.single_validate_block(deserialized_block)
              true
            catch
              {:error, _message} ->
                false
            end
          :error ->
            false
        end
      end)

    List.foldl(filtered_blocks_list, %{}, fn({block_hash, block_data}, acc) ->
        Map.put(acc, block_hash, block_data)
      end)
  end
end
