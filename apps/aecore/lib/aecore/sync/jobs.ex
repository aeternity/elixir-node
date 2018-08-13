defmodule Aecore.Sync.Jobs do

  @doc """
  Creates a new jobs queue for doing some work.
  """
  @spec init_queues() :: :ok
  def init_queues do
    :jobs.add_queue(:sync_ping_workers, [{:regulators, [{:counter, [{:limit, 3}]}]}])
    && :jobs.add_queue(:sync_task_workers, [{:regulators, [{:counter, [{:limit, 10}]}]}])
    && :jobs.add_queue(:sync_gossip_workers, [{:regulators, [{:counter, [{:limit, 10}]}]}]) 
  end

  def run_job(queue, fun) do
    :proc_lib.spawn(:jobs, :run, [queue, fun])
  end

  def delayed_run_job(old_worker, peed_id, task, queue, fun, delay) do
    new_worker = :proc_lib.spawn(
      fn ->
        :timer.sleep(delay)
        :jobs.run(queue, fun)
      end)
    {task, {:change_worker, peer_id, old_worker, new_worker}}
  end

  def enqueue(gossip, data, peer_ids) do
    spawn(fn ->
      case gossip do
        :block -> Enum.map(peer_ids, fn id -> """do_forward_block(data, id)""" id end)
        :tx -> Enum.map(peer_ids, fn id -> """do_forward_tx(data, id)""" id end)
      end
    end)
  end
  
end
