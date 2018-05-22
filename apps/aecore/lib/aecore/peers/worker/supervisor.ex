defmodule Aecore.Peers.Worker.Supervisor do
  @moduledoc """
    Supervisor for Peers and Sync
  """

  use Supervisor

  alias Aecore.Peers.Sync
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.PeerConnection
  alias Aecore.Peers.Worker.PeerConnectionSupervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {privkey, pubkey} =
      {<<160, 201, 72, 107, 212, 95, 216, 197, 145, 103, 254, 171, 105, 50, 65, 129, 67, 86, 101,
         117, 95, 252, 60, 45, 124, 212, 113, 162, 153, 165, 216, 93>>,
       <<154, 121, 221, 190, 251, 229, 233, 152, 87, 78, 165, 55, 76, 196, 152, 221, 142, 210, 81,
         18, 248, 95, 199, 248, 5, 7, 103, 191, 139, 138, 249, 61>>}

    children = [
      Sync,
      PeerConnectionSupervisor,
      Peers,
      :ranch.child_spec(
        :peer_pool,
        num_of_acceptors(),
        :ranch_tcp,
        [port: sync_port()],
        PeerConnection,
        %{
          port: sync_port(),
          privkey: privkey,
          pubkey: pubkey
        }
      )
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def sync_port do
    Application.get_env(:aecore, :peers)[:sync_port]
  end

  def num_of_acceptors do
    Application.get_env(:aecore, :peers)[:ranch_acceptors]
  end
end
