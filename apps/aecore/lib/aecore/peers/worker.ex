defmodule Aecore.Peers.Worker do
  @moduledoc """
  Peer manager module
  """

  use GenServer

  alias Aehttpclient.Client
  alias Aecore.Structures.Block
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aehttpclient.Client, as: HttpClient
  alias Aecore.Utils.Serialization
  alias Aecore.Peers.Scheduler, as: Scheduler


  require Logger

  @mersenne_prime 2147483647
  @peer_nonce :rand.uniform(@mersenne_prime)

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  ## Client side

  @spec add_peer(term) :: :ok | {:error, term()} | :error
  def add_peer(uri) do
    GenServer.call(__MODULE__, {:add_peer, uri})
  end

  @spec remove_peer(term) :: :ok | :error
  def remove_peer(uri) do
    GenServer.call(__MODULE__, {:remove_peer, uri})
  end

  @spec check_peers() :: :ok
  def check_peers() do
    GenServer.call(__MODULE__, :check_peers)
  end

  @spec all_peers() :: map()
  def all_peers() do
    GenServer.call(__MODULE__, :all_peers)
  end

  @spec genesis_block_header_hash() :: term()
  def genesis_block_header_hash() do
    Block.genesis_block().header
    |> BlockValidation.block_header_hash()
    |> Base.encode16()
  end


  @doc """
  Making async post requests to the users
  `type` is related to the uri e.g. /new_block
  """
  @spec broadcast_to_all({type :: atom(), data :: term()}) :: :ok | :error
  def broadcast_to_all({type, data}) do
    data = prep_data(type,data)
    GenServer.cast(__MODULE__, {:broadcast_to_all, {type, data}})
  end

  @doc """
  Gets a random peer nonce
  """
  @spec get_peer_nonce() :: integer()
  def get_peer_nonce() do
    @peer_nonce
  end

  ## Server side

  def init(initial_peers) do
    {:ok, initial_peers}
  end

def handle_call({:add_peer,uri}, _from, peers) do
    case(Client.get_info(uri)) do
      {:ok, info} ->
        case Aecore.Peers.Worker.get_peer_nonce() == info.peer_nonce do
          false ->
            if(info.genesis_block_hash == genesis_block_header_hash()) do
              updated_peers = Map.put(peers, uri, info.current_block_hash)
              Logger.info(fn -> "Added #{uri} to the peer list" end)
              {:reply, :ok, updated_peers}
            else
              Logger.error(fn ->
                "Failed to add #{uri}, genesis header hash not valid" end)
              {:reply, {:error, "Genesis header hash not valid"}, peers}
            end
          true ->
            Logger.debug(fn ->
              "Failed to add #{uri}, equal peer nonces" end)
            {:reply, {:error, "Equal peer nonces"}, peers}
        end
      :error ->
        Logger.error("GET /info request error")
        {:reply, :error, peers}
    end
  end

  def handle_call({:remove_peer, uri}, _from, peers) do
    if(Map.has_key?(peers, uri)) do
      Logger.info(fn -> "Removed #{uri} from the peer list" end)
      {:reply, :ok, Map.delete(peers, uri)}
    else
      Logger.error(fn -> "#{uri} is not in the peer list" end)
      {:reply, {:error, "Peer not found"}, peers}
    end
  end

  @doc """
  Filters the peers map by checking if the response status from a GET /info
  request is :ok and if the genesis block hash is the same as the one
  in the current node. After that the current block hash for every peer
  is updated if the one in the latest GET /info request is different.
  """
  def handle_call(:check_peers, _from, peers) do
    filtered_peers = :maps.filter(fn(peer, _) ->
        case Client.get_info(peer) do
          {:ok, info} -> info.genesis_block_hash == genesis_block_header_hash()
          _ -> false
        end
      end, peers)
    updated_peers =
      for {peer, current_block_hash} <- filtered_peers, into: %{} do
        {_, info} = Client.get_info(peer)
        if(info.current_block_hash != current_block_hash) do
          {peer, info.current_block_hash}
        else
          {peer, current_block_hash}
        end
      end
    Logger.info(fn ->
      "#{Enum.count(peers) - Enum.count(filtered_peers)} peers were removed after the check" end)
    {:reply, :ok, updated_peers}
  end

  def handle_call(:all_peers, _from, peers) do
    {:reply, peers, peers}
  end

  ## Async operations

  def handle_cast({:broadcast_to_all, {type, data}}, peers) do
    send_to_peers(type, data, Map.keys(peers))
    {:noreply, peers}
  end

  def handle_cast(any, peers) do
    Logger.info("[Peers] Unhandled cast message:  #{inspect(any)}")
    {:noreply, peers}
  end

  ## Internal functions
  defp send_to_peers(uri, data, peers) do
    for peer <- peers do
      HttpClient.post(peer, data, uri)
    end
  end

  defp prep_data(:new_tx, %{}=data), do: Serialization.tx(data, :serialize)
  defp prep_data(:new_block, %{}=data), do: Serialization.block(data, :serialize)

end
