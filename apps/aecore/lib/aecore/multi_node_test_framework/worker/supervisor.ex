defmodule Aecore.MultiNodeTestFramework.Worker.Supervisor do
  @moduledoc """
  Supervisor responsible for all of the worker modules in his folder
  """

  use Supervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      Aecore.MultiNodeTestFramework.Worker
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
