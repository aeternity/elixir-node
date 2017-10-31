defmodule Aecore.Txs.Pool.Worker do
  @moduledoc """
  Module for working with the transaction pool.
  The pool itself is a map with an empty initial state.
  """

  use GenServer

  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.SignedTx
  alias Aecore.Peers.Worker, as: Peers
  require Logger

  def start_link do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(initial_pool) do
    {:ok, initial_pool}
  end

  @spec add_transaction(%SignedTx{}) :: :ok | :error
  def add_transaction(tx) do
    GenServer.call(__MODULE__, {:add_transaction, tx})
  end

  @spec remove_transaction(%SignedTx{}) :: :ok
  def remove_transaction(tx) do
    GenServer.call(__MODULE__, {:remove_transaction, tx})
  end

  @spec get_pool() :: map()
  def get_pool() do
    GenServer.call(__MODULE__, :get_pool)
  end

  @spec get_and_empty_pool() :: map()
  def get_and_empty_pool() do
    GenServer.call(__MODULE__, :get_and_empty_pool)
  end

  def handle_call({:add_transaction, tx}, _from, tx_pool) do
    is_tx_valid = Keys.verify(tx.data, tx.signature, tx.data.from_acc)
    if is_tx_valid do
      updated_pool = Map.put_new(tx_pool, :crypto.hash(:sha256, :erlang.term_to_binary(tx)), tx)
      case tx_pool == updated_pool do
        true -> Logger.info(" This transaction has already been added")
        false -> Peers.broadcast_tx(tx)
      end
      {:reply, :ok, updated_pool}
    else
      {:reply, :error, tx_pool}
    end
  end

  def handle_call({:remove_transaction, tx}, _from, tx_pool) do
    {_, updated_pool} = Map.pop(tx_pool, :crypto.hash(:sha256, :erlang.term_to_binary(tx)))
    {:reply, :ok, updated_pool}
  end

  def handle_call(:get_pool, _from, tx_pool) do
    {:reply, tx_pool, tx_pool}
  end

  def handle_call(:get_and_empty_pool, _from, tx_pool) do
    {:reply, tx_pool, %{}}
  end

end
