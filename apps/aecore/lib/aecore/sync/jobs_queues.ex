defmodule Aecore.Sync.JobsQueues do
  def run(queue, fun) when is_function(fun, 0) do
    time = :erlang.system_time(:microsecond)

    case :jobs.ask(queue) do
      {:ok, opaque} ->
        log_outcome(queue, :accepted, time)

      {:error, reason} ->
        log_outcome(queue, :rejected, time)
    end
  end

  def log_outcome(queue, result, time) when result == :rejected or result == :accepted do
    t1 = :erlang.system_time(:microsecond)
  end
end
