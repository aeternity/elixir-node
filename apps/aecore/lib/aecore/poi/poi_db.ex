defmodule Aecore.Poi.PoiDB do
  use GenServer

  def prepare_for_requests(db) do
    GenServer.start_link(__MODULE__, db, name: __MODULE__)
  end

  def init(db) do
    {:ok, db}
  end

  def finilize() do
    state = GenServer.call(__MODULE__, {:finilize})
    :ok = GenServer.stop(__MODULE__)
    state
  end

  def put(key, value) do
    GenServer.call(__MODULE__, {:put, key, value})
  end

  def handle_call({:finilize}, _from, state) do
    {:reply, state, %{}}
  end

  def handle_call({:put, key, value}, _from, state) do
    {:reply, :ok, Map.put(state, key, value)}
  end

end

