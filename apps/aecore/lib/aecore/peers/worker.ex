defmodule Aecore.Peers.Worker do
  @moduledoc """
  Peer manager module
  """

  use GenServer

  alias Aehttpclient.Client
  alias Aecore.Structures.Block
  alias Aecore.Utils.Blockchain.BlockValidation

  require Logger

  def start_link do
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
    Block.genesis_header()
    |> BlockValidation.block_header_hash()
    |> Base.encode16()
  end

  @spec send_block(block :: map()) :: :ok | :error
  def send_block(block) do
    GenServer.cast(__MODULE__, {:send_block, block})
  end

  ## Server side

  def init(initial_peers) do
    {:ok, initial_peers}
  end

  def handle_call({:add_peer,uri}, _from, peers) do
    case(Client.get_info(uri)) do
      {:ok, info} ->
        if(info.genesis_block_hash == genesis_block_header_hash()) do
          updated_peers = Map.put(peers, uri, info.current_block_hash)
          Logger.info(fn -> "Added #{uri} to the peer list" end)
          {:reply, :ok, updated_peers}
        else
          Logger.error(fn ->
            "Failed to add #{uri}, genesis header hash not valid" end)
          {:reply, {:error, "Genesis header hash not valid"}, peers}
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
        {status, info} = Client.get_info(peer)
        :ok == status && info.genesis_block_hash == genesis_block_header_hash()
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

  def handle_cast({:send_block, b}, peers) do
    Aehttpclient.Client.send_block({b, peers})
    {:noreply,  peers}
  end
  def handle_cast(_any, peers) do
    {:noreply, peers}
  end
end
