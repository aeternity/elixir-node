defmodule Aecore.Peers.Scheduler do
  use GenServer

  alias Aecore.Peers.Worker, as: Peers

  @check_time 60_000
  @peer_nonce :rand.uniform(2147483647)

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_peer_nonce() do
    IO.inspect "get_nonce"
    GenServer.call(__MODULE__, :get_peer_nonce)
  end

  def init(state) do
    IO.inspect "init"
    schedule_work()
    {:ok, state}
  end

  def handle_info(:work, state) do
    Peers.check_peers()
    schedule_work()
    {:noreply, state}
  end

  def handle_call(:get_peer_nonce, _from, state) do
    IO.inspect "handlecall"
    {:reply, @peer_nonce, state}
  end

  defp schedule_work() do
    Process.send_after(self(), :work, @check_time)
  end
end
