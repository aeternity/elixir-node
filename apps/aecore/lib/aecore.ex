defmodule Aecore do
  use Application

  def start(_type, _args) do
    children = [
      Aecore.Keys.Worker.Supervisor,
      Aecore.Chain.Worker.Supervisor,
      Aecore.Miner.Worker.Supervisor,
      Aecore.Txs.Pool.Worker.Supervisor,
      Aecore.Peers.Worker.Supervisor,
      Aecore.Persistence.Worker.Supervisor
    ]
    
    Application.put_env(:aecore, :authorization, UUID.uuid4)
    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
