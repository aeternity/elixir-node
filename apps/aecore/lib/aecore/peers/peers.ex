defmodule Aecore.Peers.Peers do
  use GenServer

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Peers.Peer
  alias Aecore.Peers.Worker.PeerConnectionSupervisor

  require Logger

  def start_link(_args) do
    peers = %{}
    blocked = %{}
    local_peer = %{seckey: Wallet.get_private_key(), pubkey: Wallet.get_public_key()}
    state = %{peers: peers, blocked: blocked, local_peer: local_peer}
    GenServer.start_link(__MODULE__, state, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  def add(peer_info) do
    GenServer.cast(__MODULE__, {:add, peer_info})
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_cast(
        {:add, peer_info},
        %{peers: peers, local_peer: %{seckey: seckey, pubkey: pubkey}} = state
      ) do
    peer = Peer.new(%{host: peer_info.host, port: peer_info.port, pubkey: peer_info.pubkey})

    if peer_info.pubkey != pubkey do
      new_peer =
        if !Map.has_key?(peers, peer_info.pubkey) do
          if !Map.has_key?(peer_info, :ping) do
            conn_info =
              Map.merge(peer_info, %{r_pubkey: peer_info.pubkey, seckey: seckey, pubkey: pubkey})

            {:ok, pid} = PeerConnectionSupervisor.start_peer_connection(conn_info)
            %{peer | connection: {:pending, pid}}
          else
            %{peer | connection: :undefined}
          end
        else
          peer
        end

      updated_state = %{
        state
        | peers: Map.put(peers, new_peer.pubkey, new_peer)
      }

      {:noreply, updated_state}
    else
      Logger.error("Can't add ourself")
      {:noreply, state}
    end
  end
end
