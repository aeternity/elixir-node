defmodule Aecore.Peers.Worker.Supervisor do
  use Supervisor

  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.PeerConnection
  alias Aecore.Peers.Worker.PeerConnectionSupervisor
  alias Aecore.Keys.Peer, as: PeerKeys

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {pubkey, privkey} = PeerKeys.keypair()

    children = [
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

    Supervisor.init(children, strategy: :one_for_all)
  end

  def sync_port do
    Application.get_env(:aecore, :peers)[:sync_port]
  end

  def num_of_acceptors do
    Application.get_env(:aecore, :peers)[:ranch_acceptors]
  end
end
