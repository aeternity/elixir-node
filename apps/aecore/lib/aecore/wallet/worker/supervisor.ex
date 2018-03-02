defmodule Aecore.Wallet.Worker.Supervisor do
  use Supervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      Aecore.Wallet.Worker
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
