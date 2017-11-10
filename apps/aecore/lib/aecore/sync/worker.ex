defmodule Aecore.Sync.Worker do
  use GenServer

  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Serialization
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aehttpclient.Client, as: HttpClient

  require Logger

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
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
