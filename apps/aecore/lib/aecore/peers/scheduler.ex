defmodule Aecore.Peers.Scheduler do
  use GenServer

  alias Aecore.Peers.Sync, as: PeersSync

  @check_time 60_000

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    Process.send_after(self(), :work, 5_000)
    {:ok, state}
  end

  def handle_info(:work, state) do
    PeersSync.remove_dead()
    PeersSync.refill()
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, @check_time)
  end
end
