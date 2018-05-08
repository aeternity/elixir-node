defmodule Aecore.Peers.Worker.Supervisor do
  use Supervisor

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.PeerConnection
  alias Aecore.Peers.Worker.PeerConnectionSupervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {privkey, pubkey} =
      {<<64, 250, 58, 12, 14, 91, 253, 253, 19, 225, 68, 114, 136, 0, 231, 210, 81, 246, 43, 30,
         182, 47, 62, 86, 106, 135, 77, 93, 215, 185, 127, 73>>,
       <<88, 147, 90, 185, 185, 105, 41, 59, 173, 111, 179, 5, 135, 38, 11, 2, 84, 47, 133, 118,
         178, 240, 121, 189, 167, 220, 203, 43, 66, 247, 136, 56>>}

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

    Supervisor.init(children, strategy: :one_for_one)
  end

  def sync_port do
    Application.get_env(:aecore, :peers)[:sync_port]
  end

  def num_of_acceptors do
    Application.get_env(:aecore, :peers)[:ranch_acceptors]
  end
end
