defmodule Aecore.Peers.Supervisor do
  use Supervisor

  def start_link() do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      worker(Aecore.Peers.Worker, [])
    ]

    supervise(children, strategy: :one_for_one)
  end
end
