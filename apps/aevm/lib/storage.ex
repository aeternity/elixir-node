defmodule Aevm.Storage do
  @moduledoc """
  Module for working with the VM's internal storage
  """

  alias Aevm.State

  @spec sstore(integer(), integer(), map()) :: map()
  def sstore(key, value, %{storage: storage} = state) do
    new_storage = store(key, value, storage)
    State.set_storage(new_storage, state)
  end

  @spec sload(integer(), map()) :: map()
  def sload(key, %{storage: storage}) do
    Map.get(storage, key, 0)
  end

  defp store(key, 0, storage) do
    Map.delete(storage, key)
  end

  defp store(key, value, storage) do
    Map.put(storage, key, value)
  end
end
