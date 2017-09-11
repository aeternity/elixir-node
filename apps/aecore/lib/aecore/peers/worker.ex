defmodule Aecore.Peers.Worker do
  @moduledoc """
  Module storing peers list and providing functions for peers interaction
  """
  use GenServer
  alias Aecore.Structures.Peer
  alias Worker

  def start_link() do
	  GenServer.start_link(__MODULE__, %{peers: :gb_trees.empty}, name: __MODULE__)
  end

  @doc """
  Get information of peer with supplied url
  """
  @spec info(String.t) :: {:ok, map()} | {:error, term()}
  def info(peer) do
	  GenServer.call(__MODULE__, {:info, peer})
  end

  @doc """
  Get list of all peers. The list may be big. Use with caution.
  Consider using get_random instead.
  """
  @spec all() :: {integer, tuple() | nil}
  def all() do
	  GenServer.call(__MODULE__, :all)
  end

  @doc """
  Get random peer. This may return error when no peer is known to us (unlikely).
  The peers are randomly distributed in the sorted gb_tree (due to the use of hash_uri),
  so we can find a random peer by choosing a point and getting the next peer in gb_tree.
  """
  @spec get_random() :: {:ok | :error, map() | term()}
  def get_random() do
	  GenServer.call(__MODULE__, :get_random)
  end

  @doc """
  Get url from IP and port. IP format: xxx.xxx.xxx.xxx
  """
  @spec uri_from_ip_port(String.t, String.t) :: {:ok, String.t} | {:error,term()}
  def uri_from_ip_port(ip, port) do
	  GenServer.call(__MODULE__, {:uri_from_ip_port, {ip,port}})
  end

  @doc """
  Add peer by url
  """
  @spec add(String.t) :: atom()
  def add(peer) do
	  GenServer.cast(__MODULE__, {:add, %{Peer.create | uri: peer,
									 last_seen: :erlang.system_time()}})
  end

  @doc """
  Remove peer by url
  """
  @spec remove(String.t) :: atom()
  def remove(peer) do
    GenServer.cast(__MODULE__, {:remove, peer})
  end

  @doc """
  Just for test purposes adds some peers
  """
  def add_some_peers() do
    for x <- 1..254, do: __MODULE__.add("http://192.168.0.#{x}:8000")
    :ok
  end

  # Callbacks
  def init(state) do
    {:ok, state}
  end

  def handle_call({:info, peer_uri}, _from, %{:peers => peers}=state) do
    reply = get_peer_info(peer_uri, peers)
    {:reply, reply, state}
  end
  def handle_call(:all, _from, %{:peers => peers}=state) do
    {:reply, peers,state}
  end
  def handle_call({:uri_from_ip_port, {ip, port}}, _from, state)
  when is_binary(ip) and is_binary(port) do
    uri = "http://" <> ip <> ":" <> port <> "/"
    {:reply, {:ok, uri}, state}
  end
  def handle_call({:uri_from_ip_port, {_ip, _port}}, _from, state) do
    {:reply, {:error, "ip and port must be String.t"},state}
  end
  def handle_call(:get_random, _from, %{:peers => peers}=state) do
    reply = get_random_peer(peers)
    {:reply, reply, state}
  end

  def handle_cast({:add, peer}, state) do
    {:noreply, add_peer(peer, state)}
  end
  def handle_cast({:remove, peer_uri}, %{peers: peers}=state) do
    hash_uri = hash_uri(peer_uri)
    case :gb_trees.is_defined(hash_uri,peers) do
      :true ->
        new_peers = :gb_trees.delete(hash_uri,peers)
        {:noreply, %{state | peers: new_peers}}
      :false ->
        {:noreply, state}
    end
  end

  # Internal functions

  defp get_peer_info(peer_uri, peers) do
    hash_uri = hash_uri(peer_uri)
    case :gb_trees.is_defined(hash_uri, peers) do
      :true ->
        {:ok, :gb_trees.get(hash_uri, peers)}
      :false ->
        {:error, "peer not found"}
    end
  end

  defp get_random_peer(peers) do
    case :gb_trees.is_empty(peers) do
      :true ->
        {:error,"we don't know any peers"}
      :false ->
        randomHash =
          (for _ <- 1..16, do: (:rand.uniform(256) - 1))
          |> List.to_string
        {largestKey, _} = :gb_trees.largest(peers)
        case largestKey < randomHash do
          :true ->
            {_, peer} = :gb_trees.smallest(peers)
            {:ok, peer}
          :false ->
            iterator = :gb_trees.iterator_from(randomHash, peers)
            {_, peer, _} = :gb_trees.next(iterator)
            {:ok, peer}
        end
    end
  end

  defp add_peer(peer, %{peers: peers}=state) do
    hash_uri = hash_uri(peer.uri)
    case :gb_trees.is_defined(hash_uri, peers) do
      :true ->
        state
      :false ->
        new_peers = :gb_trees.enter(hash_uri, peer, peers)
        %{state | peers: new_peers}
    end
  end

  defp hash_uri(http_uri) do
    :crypto.hash(:md4, http_uri) <> http_uri
  end

end

