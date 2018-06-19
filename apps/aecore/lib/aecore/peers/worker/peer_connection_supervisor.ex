defmodule Aecore.Peers.Worker.PeerConnectionSupervisor do
  @moduledoc """
  Supervises the individual peer connection GenServer processes
  """

  use DynamicSupervisor

  alias Aecore.Peers.PeerConnection

  def start_link(_args) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def start_peer_connection(conn_info) do
    DynamicSupervisor.start_child(
      __MODULE__,
      Supervisor.child_spec(
        {PeerConnection, conn_info},
        restart: :temporary
      )
    )
  end

  def init(:ok) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
