defmodule Aecore.Sync.Worker do

  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Serialization
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aehttpclient.Client, as: HttpClient

  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def get_state do
    GenServer.call(__MODULE__, :get_state)
  end

  @spec ask_peers_for_unknown_blocks() :: :ok
  def ask_peers_for_unknown_blocks() do
    GenServer.call(__MODULE__, :ask_peers_for_unknown_blocks)
  end

  @spec update_statuses() :: :ok
  def update_statuses() do
    GenServer.call(__MODULE__, :update_statuses)
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
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
      block = Chain.get_block_by_hex_hash(block_hash)
      must_be_updated = status == :bad && Map.has_key?(state, block.header.prev_hash)
      case must_be_updated do
        true ->
          {block_hash, %{peer: peer, status: :good}}
        false ->
          {block_hash, %{peer: peer, status: status}}
      end
    end

    {:reply, :ok, updated_state}
  end

  def check_peer_block(peer_uri, block_hash, blocks_with_status) do
    case Chain.get_block_by_hex_hash(block_hash) do
      {:error, _} ->
        case HttpClient.get_block({peer_uri, block_hash}) do
          {:ok, peer_block} ->
            deserialized_block = Serialization.block(peer_block, :deserialize)
            peer_block_hash =
              BlockValidation.block_header_hash(deserialized_block.header)
            status = case HttpClient.get_block({peer_uri, peer_block.header.prev_hash}) do
              {:ok, _peer_block_prev} ->
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

end
