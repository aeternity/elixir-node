defmodule Aecore.Sync.Jobs do
  @moduledoc """
  Handles the Job library
  """

  ## spawn() and :proc_lib.spawn() to be changed with Elixir func calls
  ## Maybe use Task module ??

  @type queue ::
          :sync_ping_workers
          | :sing_task_workers
          | :sing_gossip_worers

  @doc """
  Creates a new jobs queue for doing some work.
  """
  @spec init_queues() :: :ok
  def init_queues do
    :jobs.add_queue(:sync_ping_workers, [{:regulators, [{:counter, [{:limit, 3}]}]}]) &&
      :jobs.add_queue(:sync_task_workers, [{:regulators, [{:counter, [{:limit, 10}]}]}]) &&
      :jobs.add_queue(:sync_gossip_workers, [{:regulators, [{:counter, [{:limit, 10}]}]}])
  end

  def run_job(queue, fun) do
    :proc_lib.spawn(:jobs, :run, [queue, fun])
  end

  def delayed_run_job(old_worker, peer_id, task, queue, fun, delay) do
    new_worker =
      :proc_lib.spawn(fn ->
        :timer.sleep(delay)
        :jobs.run(queue, fun)
      end)

    {task, {:change_worker, peer_id, old_worker, new_worker}}
  end

  def enqueue(gossip, data, peer_ids) do
    spawn(fn ->
      case gossip do
        :block ->
          Enum.map(peer_ids, fn id ->
            :jobs.run(:sync_gossip_workers, Sync.do_forward_block(data, id))
          end)

        :tx ->
          Enum.map(peer_ids, fn id ->
            :jobs.run(:sync_gossip_workers, Sync.do_forward_tx(data, id))
          end)
      end
    end)
  end
end
