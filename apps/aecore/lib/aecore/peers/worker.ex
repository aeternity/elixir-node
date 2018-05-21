defmodule Aecore.Peers.Worker do
  use GenServer

  alias Aecore.Peers.Worker.PeerConnectionSupervisor

  require Logger

  def start_link(_args) do
    peers = %{}

    {privkey, pubkey} =
      {<<160, 201, 72, 107, 212, 95, 216, 197, 145, 103, 254, 171, 105, 50, 65, 129, 67, 86, 101,
         117, 95, 252, 60, 45, 124, 212, 113, 162, 153, 165, 216, 93>>,
       <<154, 121, 221, 190, 251, 229, 233, 152, 87, 78, 165, 55, 76, 196, 152, 221, 142, 210, 81,
         18, 248, 95, 199, 248, 5, 7, 103, 191, 139, 138, 249, 61>>}

    local_peer = %{privkey: privkey, pubkey: pubkey}
    state = %{peers: peers, local_peer: local_peer}
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  def all_peers do
    GenServer.call(__MODULE__, :all_peers)
  end

  def add_peer(conn_info) do
    GenServer.call(__MODULE__, {:add_peer, conn_info})
  end

  def remove_peer(pubkey) do
    GenServer.call(__MODULE__, {:remove_peer, pubkey})
  end

  def have_peer?(peer_pubkey) do
    GenServer.call(__MODULE__, {:have_peer?, peer_pubkey})
  end

  def get_random(number) do
    GenServer.call(__MODULE__, {:get_random, number})
  end

  def try_connect(peer_info) do
    GenServer.cast(__MODULE__, {:try_connect, peer_info})
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:all_peers, _from, %{peers: peers} = state) do
    all_peers = Map.values(peers)
    {:reply, all_peers, state}
  end

  def handle_call(
        {:add_peer, %{pubkey: pubkey} = peer_info},
        _from,
        %{peers: peers} = state
      ) do
    updated_peers = Map.put(peers, pubkey, peer_info)
    updated_state = %{state | peers: updated_peers}
    {:reply, :ok, updated_state}
  end

  def handle_call({:remove_peer, pubkey}, _from, %{peers: peers} = state) do
    updated_peers = Map.delete(peers, pubkey)
    updated_state = %{state | peers: updated_peers}
    {:reply, :ok, updated_state}
  end

  def handle_call({:have_peer?, peer_pubkey}, _from, %{peers: peers} = state) do
    have_peer = Map.has_key?(peers, peer_pubkey)
    {:reply, have_peer, state}
  end

  def handle_call({:get_random, number}, _from, %{peers: peers} = state) do
    random = Enum.take_random(peers, number)
    {:reply, random, state}
  end

  def handle_cast(
        {:try_connect, peer_info},
        %{peers: peers, local_peer: %{privkey: privkey, pubkey: pubkey}} = state
      ) do
    # if peer_info.pubkey != pubkey do
    if !Map.has_key?(peers, peer_info.port) do
      conn_info =
        Map.merge(peer_info, %{r_pubkey: peer_info.pubkey, privkey: privkey, pubkey: pubkey})

      {:ok, _pid} = PeerConnectionSupervisor.start_peer_connection(conn_info)
      new_peers = Map.put_new(peers, peer_info.pubkey, peer_info)
      {:noreply, %{state | peers: new_peers}}
    else
      Logger.info(fn -> "Won't add #{inspect(peer_info)}, already in peer list" end)
      {:noreply, state}
    end
  end

  def peer_id(peer_id) when is_binary(peer_id) do
    peer_id
  end

  def peer_id({_, %{connection: peer_id}}) do
    peer_id
  end
end
