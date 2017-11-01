defmodule Aecore.Persistence.Worker do
  @moduledoc """
  Store/Restore latest blockchain and chainstate
  """

  @persistence_table Application.get_env(:aecore, :persistence)[:table]

  use GenServer

  alias Aecore.Chain.Worker, as: Chain

  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec restore_blockchain() :: {:ok, list()} | {:error, reason :: term()}
  def restore_blockchain() do
    GenServer.call(__MODULE__, :blockchain)
  end

  @spec restore_chainstate() :: {:ok, list()} | {:error, reason :: term()}
  def restore_chainstate() do
    GenServer.call(__MODULE__, :chainstate)
  end

  def init(_) do
    ## Ensures that the worker handles exit signals
    Process.flag(:trap_exit, true)
    {:ok, setup()}
  end

  def handle_call(:blockchain, _from, %{table: nil}=state) do
    {:reply, {:error, "failed on reading persistence db"}, state}
  end

  def handle_call(:blockchain, _from, %{table: table}=state) do
    reply = :dets.lookup(table, :blockchain)
    {:reply, {:ok, reply}, state}
  end

  def handle_call(:chainstate, _from, %{table: table}=state) do
    reply = :dets.lookup(table, :chainstate)
    {:reply, {:ok, reply}, state}
  end

  def handle_cast(_any, state) do
    {:noreply, state}
  end

  def terminate(_, %{table: nil}=state), do: Logger.error("No db connection")
  def terminate(_, %{table: table}=state) do
    Aecore.Miner.Worker.suspend
    :ok = :dets.insert(table, {:blockchain, Chain.all_blocks()})
    :ok = :dets.insert(table, {:chainstate, Chain.chain_state()})
    Logger.info("Terminating, blockchain and chainstate were stored to disk")
  end

  ## Internal functions

  defp setup do
    {:ok, table} = :dets.open_file(@persistence_table , [type: :set])
    %{table: table}
  end

end
