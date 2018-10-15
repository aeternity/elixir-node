defmodule Aecore.Poi.PoiPersistence do
  @moduledoc """
  Implements a wrapper encapsulating the side effects of PatriciaMerkleTree.
  When any writing to the proof database is needed the wrapper is initialized with the
  current database and then after changes to the database were made the wrapper returns
  the updated database. It introduces a 2x memory overhead as we need to copy the current
  database to the child process - It's not an issue as our Poi's currently contain at most a few accounts.
  """

  use GenServer

  @type proof_key_value_store :: map()

  @doc """
  Initializes the wrapper with the current database
  """
  @spec prepare_for_requests(proof_key_value_store()) :: GenServer.on_start()
  def prepare_for_requests(key_value_store) do
    GenServer.start_link(__MODULE__, key_value_store, name: __MODULE__)
  end

  @doc """
  Initializes the state of the wrapper
  """
  @spec init(proof_key_value_store()) :: {:ok, proof_key_value_store()}
  def init(key_value_store) do
    {:ok, key_value_store}
  end

  @doc """
  Finalizes the put requests made to the wrapper and returns the updated state.
  This function must only be called after calling prepare_for_requests.
  """
  @spec finalize :: proof_key_value_store()
  def finalize do
    state = GenServer.call(__MODULE__, {:finalize})
    :ok = GenServer.stop(__MODULE__)
    state
  end

  @doc """
  Puts an item to the database.
  This function must only be called after calling prepare_for_requests and before finalize was called.
  """
  @spec put(binary(), binary()) :: :ok
  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  # Server side

  def handle_call({:finalize}, _from, state) do
    {:reply, state, %{}}
  end

  def handle_call({:put, key, value}, _from, state) do
    {:reply, :ok, Map.put(state, key, value)}
  end
end
