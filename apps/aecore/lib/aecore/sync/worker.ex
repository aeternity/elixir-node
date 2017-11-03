defmodule Aecore.Sync.Worker do

  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Serialization
  alias Aehttpclient.Client, as: HttpClient

  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  @spec ask_peers_for_latest_block() :: :ok
  def ask_peers_for_latest_block() do
    GenServer.call(__MODULE__, :ask_peers_for_latest_block)
  end

  def handle_call(:ask_peers_for_latest_block, _from, state) do
    all_peers = Peers.all_peers()
    Enum.each(all_peers, fn {uri, latest_block_hash} ->
        check_peer_block(uri, latest_block_hash)
      end)

    {:reply, :ok, state}
  end

  def check_peer_block(peer_uri, block_hash) do
    case Chain.get_block_by_hex_hash(block_hash) do
      {:error, _} ->
        case HttpClient.get_block({peer_uri, block_hash}) do
          {:ok, peer_block} ->
            deserialized_block = Serialization.block(peer_block, :deserialize)
            Chain.add_block(deserialized_block)
            check_peer_block(peer_uri, peer_block.header.prev_hash)
          :error ->
            {:error, "Couldn't get block from peer"}
        end
      _ ->
        "Block already in our chain"
    end
  end

end
