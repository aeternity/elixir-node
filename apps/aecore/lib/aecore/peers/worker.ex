defmodule Aecore.Peers.Worker do

  alias Aehttpclient.Client

  use GenServer

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def init(initial_peers) do
    {:ok, initial_peers}
  end

  @spec add_peer(term) :: :ok | :error
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

  @spec all_peers() :: list()
  def all_peers() do
    GenServer.call(__MODULE__, :all_peers)
  end

  def handle_call({:add_peer,uri}, _from, peers) do
    case(Client.ping_uri(uri)) do
      :ok ->
        {:reply, :ok, [uri | peers]}
      :error ->
        {:reply, :error, peers}
    end
  end

  def handle_call({:remove_peer, uri}, _from, peers) do
    if(Enum.member?(peers,uri)) do
      {:reply, :ok, List.delete(peers, uri)}
    else
      {:reply, :error, peers}
    end
  end

  def handle_call(:check_peers, _from, peers) do
    updated_peers = Enum.filter(peers, fn(peer) ->
      reply = Client.ping_uri(peer)
      :ok = reply
      end)
    {:reply, :ok, updated_peers}
  end

  def handle_call(:all_peers, _from, peers) do
    {:reply, peers, peers}
  end
end
