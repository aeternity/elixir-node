defmodule Aecore.Miner.Worker.Supervisor do
  use Supervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      Aecore.Miner.Worker
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
