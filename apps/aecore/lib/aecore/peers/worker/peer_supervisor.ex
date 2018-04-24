defmodule Aecore.Peers.Worker.PeerSupervisor do
  use Supervisor

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Peers.Peers
  alias Aecore.Peers.PeerConnection
  alias Aecore.Peers.Worker.PeerConnectionSupervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    privkey = Wallet.get_private_key()
    pubkey = Wallet.get_public_key()

    children = [
      PeerConnectionSupervisor,
      Peers,
      # :ranch.child_spec(
      #   :peer_pool,
      #   num_of_acceptors(),
      #   :ranch_tcp,
      #   [port: sync_port()],
      #   PeerConnection,
      #   %{
      #     port: sync_port(),
      #     privkey: privkey,
      #     pubkey: pubkey
      #   }
      # )
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
