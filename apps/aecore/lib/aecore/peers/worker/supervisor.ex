defmodule Aecore.Peers.Worker.Supervisor do
  @moduledoc """
  Supervises the Peers, PeerConnectionSupervisor, Sync and ranch acceptor processes with a one_for_all strategy
  """

  use Supervisor

  alias Aecore.Sync.Sync
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.PeerConnection
  alias Aecore.Peers.Worker.PeerConnectionSupervisor
  alias Aecore.Keys

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {pubkey, privkey} = Keys.keypair(:peer)

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

    Supervisor.init(children, strategy: :one_for_all)
  end

  def sync_port do
    Application.get_env(:aecore, :peers)[:sync_port]
  end

  def num_of_acceptors do
    Application.get_env(:aecore, :peers)[:ranch_acceptors]
  end
end
