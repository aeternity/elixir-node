defmodule Aecore.Peers.Jobs do
  @moduledoc """
  Module for handling the encqueue and dequeue of a job
  and following the number of enqueued jobs.
  """

  use GenServer

  alias Aecore.Peers.Sync

  def start_link(_args) do
    GenServer.start(__MODULE__, %{queues: []}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  @spec add_queue(atom()) :: :ok | {:error, String.t()}
  def add_queue(queue) do
    GenServer.call(__MODULE__, {:add_queue, queue})
  end

  def enqueue(queue, job) do
    GenServer.cast(__MODULE__, {:enqueue, queue, job})
  end

  def dequeue(queue) do
    GenServer.cast(__MODULE__, {:dequeue, queue})
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:add_queue, queue}, _from, %{queues: queues} = state) do
    if Keyword.has_key?(queues, queue) do
      {:reply, {:error, "This queue is already active"}, state}
    else
      case :jobs.queue_info(queue) do
        :undefined ->
          :ok = :jobs.add_queue(queue, [:passive])
          {:reply, :ok, %{state | queues: Keyword.put_new(queues, queue, 0)}}

        _ ->
          {:reply, {:error, "This queue is already active"}, state}
      end
    end
  end

  def handle_cast({:enqueue, queue, job}, %{queues: queues} = state) do
    if Keyword.has_key?(queues, queue) do
      updated_queue = Keyword.update!(queues, queue, &(&1 + 1))
      :jobs.enqueue(queue, job)
      {:noreply, %{state | queues: updated_queue}}
    else
      {:noreply, state}
    end
  end

  def handle_cast({:dequeue, queue}, %{queues: queues} = state) do
    if Keyword.has_key?(queues, queue) do
      amount = Keyword.get(queues, queue)

      if amount != 0 do
        jobs = :jobs.dequeue(queue, amount)
        Sync.process_jobs(jobs)
      end

      updated_queue = Keyword.update!(queues, queue, &(&1 * 0))
      {:noreply, %{state | queues: updated_queue}}
    else
      {:noreply, state}
    end
  end
end
