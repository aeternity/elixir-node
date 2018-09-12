defmodule Aecore.Persistence.Worker.Supervisor do
  @moduledoc """
  Supervisor responsible for all of the worker modules in his folder
  """

  use Supervisor

  @spec start_link([
          {:debug, [:log | :statistics | :trace | {any(), any()}]}
          | {:name, atom() | {:global, any()} | {:via, atom(), any()}}
          | {:spawn_opt,
             :link
             | :monitor
             | {:fullsweep_after, non_neg_integer()}
             | {:min_bin_vheap_size, non_neg_integer()}
             | {:min_heap_size, non_neg_integer()}
             | {:priority, :high | :low | :normal}}
          | {:timeout, :infinity | non_neg_integer()}
        ]) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(args) do
    Supervisor.start_link(__MODULE__, :ok, args)
  end

  def init(:ok) do
    children = [
      Aecore.Persistence.Worker
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
