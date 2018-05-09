defmodule Aecore.Peers.Worker.PeerConnectionSupervisor do
  @moduledoc """
  Supervises the individual peer connection GenServer processes
  """

  use Supervisor

  alias Aecore.Peers.PeerConnection

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_peer_connection(conn_info) do
    Supervisor.start_child(
      __MODULE__,
      Supervisor.child_spec({PeerConnection, conn_info}, id: :peer_connection)
    )
  end

  def init(:ok) do
    children = []

    Supervisor.init(children, strategy: :one_for_one)
  end
end
