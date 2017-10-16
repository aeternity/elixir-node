defmodule Aecore do
  use Application

  alias Aecore.Miner.Worker, as: Miner

  def start(_type, _args) do
    import Supervisor.Spec

    children = [supervisor(Aecore.Keys.Worker.Supervisor, []), supervisor(Aecore.Chain.Worker.Supervisor, []),
      supervisor(Aecore.Miner.Worker.Supervisor, []), supervisor(Aecore.Txs.Pool.Worker.Supervisor,[])]

	  Supervisor.start_link(children, strategy: :one_for_one)
  end
end
