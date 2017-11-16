defmodule Aecore.Peers.Scheduler do
  use GenServer

  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.Sync

  @check_time 60_000

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    schedule_work()
    {:ok, state}
  end

  def handle_info(:work, state) do
    Peers.check_peers()
    Sync.introduce_variety()
    Sync.refill()
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, @check_time)
  end
end
