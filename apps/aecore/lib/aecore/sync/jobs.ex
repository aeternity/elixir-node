defmodule Aecore.Sync.Jobs do
  @moduledoc """
  Handles the functionality of scheduling the required jobs for the sync to be done.
  This implementations uses the `job` library, where each job is regulated to a specific queue.

  We have 3 main queues:
  - `:sync_ping_workers` -> Handles the ping between nodes
  - `:sync_task_workers` -> Handles the required functions for synchronization
  - `:sync_gossip_workers` -> Handles the gossiping of blocks | txs

  Each job function is spawned in a separate process using Task.start()
  Later in the Sync module these processes are linked to the GenServer process of the Sync module
  """

  alias Aecore.Sync.Sync
  alias Aecore.Sync.Task, as: SyncTask
  alias Aecore.Chain.Block
  alias Aecore.Tx.SignedTx

  @type peer_id :: pid()
  @type delay :: non_neg_integer()
  @type gossip :: :block | :tx
  @type queue ::
          :sync_ping_workers
          | :sync_task_workers
          | :sync_gossip_worers

  @doc """
  Creates a new jobs queue for doing some work.
  """
  @spec init_queues() :: :ok
  def init_queues do
    :jobs.add_queue(:sync_ping_workers, [{:regulators, [{:counter, [{:limit, 3}]}]}]) &&
      :jobs.add_queue(:sync_task_workers, [{:regulators, [{:counter, [{:limit, 10}]}]}]) &&
      :jobs.add_queue(:sync_gossip_workers, [{:regulators, [{:counter, [{:limit, 10}]}]}])
  end

  @spec run_job(queue(), fun()) :: {:ok, pid()}
  def run_job(queue, fun) do
    Task.start(:jobs, :run, [queue, fun])
  end

  @spec delayed_run_job(peer_id(), SyncTask.t(), queue(), fun(), delay()) ::
          {SyncTask.t(), {:change_worker, peer_id(), pid(), pid()}}
  def delayed_run_job(peer_id, task, queue, fun, delay) do
    old_worker = self()

    {:ok, new_worker} =
      Task.start(fn ->
        :timer.sleep(delay)
        :jobs.run(queue, fun)
      end)

    {task, {:change_worker, peer_id, old_worker, new_worker}}
  end

  @spec enqueue(gossip(), Block.t() | SignedTx.t(), list(peer_id())) :: {:ok, pid()}
  def enqueue(gossip, data, peer_ids) do
    Task.start(fn ->
      Enum.map(peer_ids, fn peer_id ->
        :jobs.run(:sync_gossip_workers, enqueue_strategy(gossip, data, peer_id))
      end)
    end)
  end

  defp enqueue_strategy(:block, block, peer_id) do
    fn -> Sync.forward_block(block, peer_id) end
  end

  defp enqueue_strategy(:tx, tx, peer_id) do
    fn -> Sync.forward_tx(tx, peer_id) end
  end
end
