defmodule Aetestframework.Worker.Supervisor do
  @moduledoc """
  Supervisor responsible for all of the worker modules in his folder
  """

  use Supervisor

  def start_link do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    children = [
      Aetestframework.Worker
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
