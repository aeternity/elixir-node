defmodule Aecore do
  use Application
  import Supervisor.Spec

  def start(_type, _args) do
    children = [
      Aecore.Keys.Worker.Supervisor,
      Aecore.Persistence.Worker.Supervisor,
      Aecore.Chain.Worker.Supervisor,
      Aecore.Miner.Worker.Supervisor,
      Aecore.Txs.Pool.Worker.Supervisor,
      Aecore.Peers.Worker.Supervisor,
      supervisor(Exexec, [], function: :start)
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
