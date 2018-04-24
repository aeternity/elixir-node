defmodule Aecore do
  @moduledoc """
  Supervisor responsible for all of the worker modules in his folder
  """

  use Application

  import Supervisor.Spec

  def start(_type, _args) do
    {:ok, _} = :ranch.start_listener(:peer_pool, 100,
        :ranch_tcp, [{:port, 3015}],
        Aecore.Peers.PeerConnection, []
)
    children = [
      Aecore.Persistence.Worker.Supervisor,
      Aecore.Chain.Worker.Supervisor,
      Aecore.Miner.Worker.Supervisor,
      Aecore.Tx.Pool.Worker.Supervisor,
      Aecore.Peers.Worker.Supervisor,
      Aecore.Wallet.Worker.Supervisor,
      Aecore.Peers.Worker.PeerSupervisor,
      supervisor(Exexec, [], function: :start)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
