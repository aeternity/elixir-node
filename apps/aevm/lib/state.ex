defmodule State do
  def init_vm() do
    state = %{
      :stack => [],
      :memory => %{}
    }
  end

  def set_stack(stack, state) do
    Map.put(state, :stack, stack)
  end

  def set_memory(memory, state) do
    Map.put(state, :memory, memory)
  end

  def stack(state) do
    Map.get(state, :stack)
  end

  def memory(state) do
    Map.get(state, :memory)
  end
end
