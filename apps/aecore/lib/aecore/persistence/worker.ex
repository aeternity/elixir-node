defmodule Aecore.Persistence.Worker do
  @moduledoc """
  Store/Restore latest blockchain and chainstate
  """

  @persistence_table Application.get_env(:aecore, :persistence)[:table]
  @blockchain_key :block_chain_state_key

  use GenServer

  alias Aecore.Chain.Worker, as: Chain

  require Logger

  def start_link(_arg) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @spec restore_blockchain() :: {:ok, list()} | {:error, term()}
  def restore_blockchain() do
    GenServer.call(__MODULE__, :restore_blockchain)
  end

  def init(_) do
    ## Ensures that the worker handles exit signals
    Process.flag(:trap_exit, true)
    {:ok, []}
  end

  def handle_call(:restore_blockchain, _from, state) do
    {:reply, get_block_chain_states(), state}
  end

  def handle_cast(_any, state) do
    {:noreply, state}
  end

  def terminate(_, _) do
    Aecore.Miner.Worker.suspend
    {:ok, table} = :dets.open_file(@persistence_table , [type: :set])
    :ok = :dets.insert(table, {@blockchain_key, Chain.get_current_state()})
    halt_dets(table)
    Logger.info("Terminating, blockchain and chainstate were stored to disk")
  end

  ## Internal functions

  @spec get_block_chain_states() :: {:ok, term()}
  defp get_block_chain_states() do
    {:ok, table} = :dets.open_file(@persistence_table , [type: :set])
    resp = case :dets.lookup(table, @blockchain_key) do
             [] -> {:ok, :nothing_to_restore}
             restored_data -> {:ok, Keyword.fetch!(restored_data, @blockchain_key)}
           end
    halt_dets(table)
    resp
  end

  defp halt_dets(table) do
    :dets.close(table)
    :dets.stop()
  end

end
