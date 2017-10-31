defmodule Aecore.Persistence.Worker do
  @moduledoc """
  TODO
  """

  use GenServer

  # alias Aehttpclient.Client
  # alias Aecore.Structures.Block
  # alias Aecore.Utils.Blockchain.BlockValidation
  # alias Aecore.Utils.Serialization

  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, %{table: nil}, name: __MODULE__)
  end

  def get_last_state() do
    GenServer.call(__MODULE__, :last_state)
  end

  def init(state) do
    {:ok, table} = :dets.open_file(:chain, [type: :set])
    Process.flag(:trap_exit, true)
    {:ok, %{state | table: table}}
  end

  def handle_call(:last_state, _from, %{table: table}=state) do
    reply = :dets.lookup(table, :blockchain)
    {:reply, reply, state}
  end

  def handle_cast(_any, state) do
    {:noreply, state}
  end

  def terminate(_, %{table: table}=state) do
    Aecore.Miner.Worker.suspend

    ## Get the blockchain state
    chain = Aecore.Chain.Worker.all_blocks
    :ok = :dets.insert(table, {:blockchain, chain})
    Logger.info("Terminating, blockchain state was stored to disk")
    ## Get the chainstate
    ## Write them to dets
    Process.sleep(10_000)
  end

end
