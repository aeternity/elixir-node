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
  alias Aecore.Peers.Sync

  require Logger

  @mersenne_prime 2147483647
  @peers_max_count Application.get_env(:aecore, :peers)[:peers_max_count]
  @probability_of_peer_remove_when_max 0.5


  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{peers: %{}, nonce: get_peer_nonce()}, name: __MODULE__)
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

  @spec schedule_add_peer(uri :: term()) :: term()
  def schedule_add_peer(uri) do
    GenServer.cast(__MODULE__, {:schedule_add_peer, uri})
  end

  @doc """
  Gets a random peer nonce
  """
  @spec get_peer_nonce() :: integer()
  def get_peer_nonce() do
    case :ets.info(:nonce_table) do
      :undefined -> create_nonce_table()
      _ -> :table_created
    end
    case :ets.lookup(:nonce_table, :nonce) do
      [] ->
        nonce = :rand.uniform(@mersenne_prime)
        :ets.insert(:nonce_table, {:nonce, nonce})
        nonce
      _ ->
        :ets.lookup(:nonce_table, :nonce)[:nonce]
    end
  end

  ## Server side

  def init(initial_peers) do
    {:ok, initial_peers}
  end

  def handle_call({:add_peer,uri}, _from, state) do
    add_peer(uri, state)
  end

  def handle_call({:remove_peer, uri}, _from, %{peers: peers} = state) do
    if(Map.has_key?(peers, uri)) do
      Logger.info(fn -> "Removed #{uri} from the peer list" end)
      {:reply, :ok, %{state | peers: Map.delete(peers, uri)}}
    else
      Logger.error(fn -> "#{uri} is not in the peer list" end)
      {:reply, {:error, "Peer not found"}, %{state | peers: peers}}
    end
  end

  @doc """
  Filters the peers map by checking if the response status from a GET /info
  request is :ok and if the genesis block hash is the same as the one
  in the current node. After that the current block hash for every peer
  is updated if the one in the latest GET /info request is different.
  """
  def handle_call(:check_peers, _from, %{peers: peers} = state) do
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
    {:reply, :ok, %{state | peers: updated_peers}}
  end

  def handle_call(:all_peers, _from, %{peers: peers} = state) do
    {:reply, peers, %{state | peers: peers}}
  end

  ## Async operations

  def handle_cast({:broadcast_to_all, {type, data}}, %{peers: peers} = state) do
    send_to_peers(type, data, Map.keys(peers))
    {:noreply, state}
  end

  def handle_cast({:schedule_add_peer, uri}, state) do
    {:reply, _, state} = add_peer(uri, state)
    {:noreply, state}
  end

  def handle_cast(any, state) do
    Logger.info("[Peers] Unhandled cast message:  #{inspect(any)}")
    {:noreply, state}
  end

  ## Internal functions
  defp add_peer(uri, state) do
    %{peers: peers} = state
    if Map.has_key?(peers, uri) do
      Logger.debug(fn ->
        "Skipped adding #{uri}, already known" end)
      {:reply, {:error, "Peer already known"}, state}
    else
      case check_peer(uri, get_peer_nonce()) do
        {:ok, info} ->
          if should_a_peer_be_added(map_size(peers)) do
            peers_update1 =
            if map_size(peers) >= @peers_max_count do
                random_peer = Enum.random(Map.keys(peers))
                Logger.debug(fn -> "Max peers reached. #{random_peer} removed" end)
                Map.delete(peers, random_peer)
              else
                peers
              end
            updated_peers = Map.put(peers_update1, uri, info.current_block_hash)
            Logger.info(fn -> "Added #{uri} to the peer list" end)
            {:reply, :ok, %{state | peers: updated_peers}}
          else
            Logger.debug(fn -> "Max peers reached. #{uri} not added" end)
            {:reply, :ok, state}
          end
        {:error, reason} ->
          Logger.error(fn -> "Failed to add peer. reason=#{reason}" end)
          {:reply, {:error, reason}, state}
      end
    end
  end

  defp create_nonce_table() do
    :ets.new(:nonce_table, [:named_table])
  end

  defp send_to_peers(uri, data, peers) do
    for peer <- peers do
      HttpClient.post(peer, data, uri)
    end
  end

  defp check_peer(uri, own_nonce) do
    case(Client.get_info(uri)) do
      {:ok, info} ->
        case own_nonce == info.peer_nonce do
          false ->
            cond do
              info.genesis_block_hash != genesis_block_header_hash() ->
                {:error, "Genesis header hash not valid"}
              !Map.has_key?(info, :server) || info.server != "aehttpserver"->
                {:error, "Peer is not an aehttpserver"}
              true ->
                {:ok, info}
            end
          true ->
            {:error, "Equal peer nonces"}
        end
      :error ->
        {:error, "Request error"}
    end
  end

  defp should_a_peer_be_added peers_count do
    peers_count < @peers_max_count
    || :rand.uniform() < @probability_of_peer_remove_when_max
  end

  defp prep_data(:new_tx, %{}=data), do: Serialization.tx(data, :serialize)
  defp prep_data(:new_block, %{}=data), do: Serialization.block(data, :serialize)

end
