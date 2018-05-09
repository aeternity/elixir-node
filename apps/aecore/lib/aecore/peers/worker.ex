defmodule Aecore.Peers.Worker do
  use GenServer

  alias Aecore.Peers.Worker.PeerConnectionSupervisor

  require Logger

  def start_link(_args) do
    peers = %{}

    {privkey, pubkey} =
      {<<64, 250, 58, 12, 14, 91, 253, 253, 19, 225, 68, 114, 136, 0, 231, 210, 81, 246, 43, 30,
         182, 47, 62, 86, 106, 135, 77, 93, 215, 185, 127, 73>>,
       <<88, 147, 90, 185, 185, 105, 41, 59, 173, 111, 179, 5, 135, 38, 11, 2, 84, 47, 133, 118,
         178, 240, 121, 189, 167, 220, 203, 43, 66, 247, 136, 56>>}

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

  def add_peer(conn_info) do
    GenServer.call(__MODULE__, {:add_peer, conn_info})
  end

  def remove_peer(pubkey) do
    GenServer.call(__MODULE__, {:remove_peer, pubkey})
  end

  def have_peer?(peer_pubkey) do
    GenServer.call(__MODULE__, {:have_peer?, peer_pubkey})
  end

  def try_connect(peer_info) do
    GenServer.cast(__MODULE__, {:try_connect, peer_info})
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
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

  def handle_cast(
        {:try_connect, peer_info},
        %{peers: peers, local_peer: %{privkey: privkey, pubkey: pubkey}} = state
      ) do
    # if peer_info.pubkey != pubkey do
    if !Map.has_key?(peers, peer_info.pubkey) do
      conn_info =
        Map.merge(peer_info, %{r_pubkey: peer_info.pubkey, privkey: privkey, pubkey: pubkey})

      {:ok, _pid} = PeerConnectionSupervisor.start_peer_connection(conn_info)

      {:noreply, state}
    else
      Logger.info(fn -> "Won't add #{inspect(peer_info)}, already in peer list" end)
      {:noreply, state}
    end

    # else
    #  Logger.error("Can't add ourself")
    #  {:noreply, state}
    # end
  end
end
