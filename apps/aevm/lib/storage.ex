defmodule Storage do
  def sstore(key, value, state) do
    storage = State.storage(state)
    new_storage = store(key, value, storage)
    State.set_storage(new_storage, state)
  end

  def sload(key, state) do
    storage = State.storage(state)
    Map.get(storage, key, 0)
  end

  defp store(key, 0, storage) do
    Map.delete(storage, key)
  end

  defp store(key, value, storage) do
    Map.put(storage, key, value)
  end
end
