defmodule Aecore.Peers.Scheduler do
  use GenServer

  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.Sync

  @check_time 60_000

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(running_tasks) do
    schedule_work()
    {:ok, running_tasks}
  end

  def add_running_task() do
    GenServer.call(__MODULE__, :add_running_task)
  end

  def remove_running_task() do
    GenServer.call(__MODULE__, :remove_running_task)
  end

  def handle_call(:add_running_task, from, running_tasks) do
    updated_tasks = Map.put(running_tasks, from, :running)

    {:reply, :ok, updated_tasks}
  end

  def handle_call(:remove_running_task, from, running_tasks) do
    updated_tasks = Map.delete(running_tasks, from)

    {:reply, :ok, updated_tasks}
  end

  def handle_info(:work, running_tasks) do
    Peers.check_peers()
    Sync.introduce_variety()
    Sync.refill()
    if(Enum.empty?(running_tasks)) do
      Sync.ask_peers_for_unknown_blocks(Peers.all_peers())
    end
    schedule_work()

    {:noreply, running_tasks}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, @check_time)
  end
end
