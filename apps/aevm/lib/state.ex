defmodule State do
  def init_vm() do
    state = %{
      :stack => [],
      :memory => %{}
    }
  end

  def set_stack(state, value) do
    Map.put(state, :stack, value)
  end

  def set_memory(state, adress, value) do
    Map.put(state, :memory, %{})
  end

  def stack(state) do
    Map.get(state, :stack)
  end

  def memory(state) do
    Map.get(state, :memory)
  end
end
