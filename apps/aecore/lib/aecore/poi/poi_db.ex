defmodule Aecore.Poi.PoiDB do
  @moduledoc """
    Implements a wrapper encapsulating the side effects of PatriciaMerkleTree.
    When any writing to the trie database is needed the wrapper is initialized with the
    current database and then after changes to the database were made the wrapper returns
    the updated database. It introduces a 2x memory overhead as we need to copy the current
    database to the child process - It's not an issue as our Poi's currently contain at most a few accounts.
  """

  use GenServer

  @doc """
    Initializes the wrapper with the current database
  """
  @spec prepare_for_requests(Map.t()) :: GenServer.on_start()
  def prepare_for_requests(db) do
    GenServer.start_link(__MODULE__, db, name: __MODULE__)
  end

  @doc """
    Initializes the state of the wrapper
  """
  @spec init(Map.t()) :: {:ok, Map.t()}
  def init(db) do
    {:ok, db}
  end

  @doc """
    Finilizes the put requests made to the wrapper and returns the updated state.
    This function must only be called after calling prepare_for_requests.
  """
  @spec finilize :: Map.t()
  def finilize do
    state = GenServer.call(__MODULE__, {:finilize})
    :ok = GenServer.stop(__MODULE__)
    state
  end

  @doc """
    Puts an item to the database.
    This function must only be called after calling prepare_for_requests and before finilize was called.
  """
  @spec put(binary(), binary()) :: :ok
  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  #Server side

  def handle_call({:finilize}, _from, state) do
    {:reply, state, %{}}
  end

  def handle_call({:put, key, value}, _from, state) do
    {:reply, :ok, Map.put(state, key, value)}
  end
end
