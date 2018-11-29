defmodule Aecore.Sync.JobsQueues do
  def run(queue, fun) when is_function(fun, 0) do
    time = :erlang.system_time(:microsecond)

    case :jobs.ask(queue) do
      {:ok, opaque} -> true
      _ -> false
    end
  end
end
