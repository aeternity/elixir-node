defmodule Aecore.Peers.Scheduler do
  use GenServer

  alias Aecore.Peers.Worker, as: Peers

  def start_link do
    GenServer.start_link(__MODULE__, %{})
  end

  def init(state) do
    schedule_work()
    {:ok, state}
  end

  def handle_info(:work, state) do
    Peers.check_peers()
    schedule_work()
    {:noreply, state}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, 60_000)
  end
end
