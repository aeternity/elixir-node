defmodule Aecore.Persistence.SupplierWorker.SupplierSupervisor do
  @moduledoc """
  Supervisor responsible for Supplier process of the worker modules.
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, :ok, args)
  end

  def init(:ok) do
    children = [
      Aecore.Persistence.Supplier
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
