defmodule Aecore.Txs.Pool.Worker.Supervisor do
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      worker(Aecore.Txs.Pool.Worker, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
