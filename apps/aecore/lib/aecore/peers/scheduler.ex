defmodule Aecore.Peers.Scheduler do
  @moduledoc """
  Performs peer related operations every @check_time milliseconds.
  """

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

  def handle_info(:work, state) do
    Peers.check_peers()
    Sync.introduce_variety()
    Sync.refill()
    Sync.ask_peers_for_unknown_blocks(Peers.all_peers())
    schedule_work()

    {:noreply, state}
  end

  defp schedule_work do
    Process.send_after(self(), :work, @check_time)
  end
end
