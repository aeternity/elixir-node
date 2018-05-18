defmodule Aecore.Peers.Worker.PeerConnectionSupervisor do
  @moduledoc """
  Supervises the individual peer connection GenServer processes
  """

  use Supervisor

  alias Aecore.Peers.PeerConnection
  alias Aecore.Peers.Worker, as: Peers

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_peer_connection(conn_info) do
    Supervisor.start_child(
      __MODULE__,
      Supervisor.child_spec({PeerConnection, conn_info}, id: conn_info.port)
    )
  end

  def stop_peer_connection(peer_pubkey) do
    Supervisor.terminate_child(__MODULE__, peer_pubkey)
    Supervisor.delete_child(__MODULE__, peer_pubkey)
    Peers.remove_peer(peer_pubkey)
    # TODO: Clean the peer from the sync_pool in the Sync module
  end

  def init(:ok) do
    children = []

    Supervisor.init(children, strategy: :one_for_one)
  end
end
