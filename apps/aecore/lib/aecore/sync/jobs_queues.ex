defmodule Aecore.Sync.JobsQueues do
  def run(queue, fun) when is_function(fun, 0) or is_function(fun, 1) do
    time = :erlang.system_time(:microsecond)

    case :jobs.ask(queue) do
      {:ok, opaque} ->
        log_outcome(queue, :accepted, time)

        try do
          case :erlang.fun_info(fun)[:arity] do
            0 -> fun.()
            1 -> fun.(opaque)
          end
        after
          :jobs.done(opaque)
        end

      {:error, reason} ->
        log_outcome(queue, :rejected, time)
        :erlang.error({:rejected, reason})
    end
  end

  def log_outcome(queue, result, time) when result == :rejected or result == :accepted do
    t1 = :erlang.system_time(:microsecond)

    try do
      :exometer.update(metric(queue, [result, :wait]), t1 - time)
      :exometer.update(metric(queue, [result, :wait]), 1)
    catch
      e -> {:error, "#{__MODULE__}: Error: #{inspect(Exception.message(e))}"}
    end
  end

  defp metric(queue, sub) do
    [:ae, :epoch, :aecore, queue | sub]
  end
end
