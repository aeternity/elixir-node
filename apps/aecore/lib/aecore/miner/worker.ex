defmodule Aecore.Miner.Worker do
  @moduledoc """
  Module for the miner
  """

  alias Aecore.Chain.Worker, as: Chain

  use GenServer

  def start_link() do
    GenServer.start_link(__MODULE__, [])
  end

  def init([]) do
    schedule_work()
    {:ok, []}
  end

  def handle_info(:work, state) do
    state = miner(state)
    schedule_work()
    {:noreply, state}
  end

  defp miner(state) do
    Chain.mine_next_block([])
  end

  defp schedule_work do
    Process.send_after(self(), :work, 0)
  end

end
