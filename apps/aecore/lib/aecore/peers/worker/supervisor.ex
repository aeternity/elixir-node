defmodule Aecore.Peers.Worker.Supervisor do
  @moduledoc """
  Supervisor responsible for all of the worker modules in his folder
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, :ok, args)
  end

  def init(:ok) do
    children = [
      Aecore.Peers.Worker,
      Aecore.Peers.Sync,
      Aecore.Peers.Scheduler
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
