defmodule State do
  def init_vm(bytecode) do
    code = bytecode_to_bin(bytecode)
    state = %{
      :stack => [],
      :memory => %{},
      :code => code,
      :cp => 0
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

  def bytecode_to_bin(bytecode) do
    chunked_bytecode =
      bytecode
      |> String.to_charlist()
      |> Enum.chunk_every(2)
      |> Enum.reduce([], fn x, acc ->
        {code, _} = x |> List.to_string() |> Integer.parse(16)

        [code | acc]
      end)
      |> Enum.reverse()
      |> List.to_string
  end

end
