defmodule State do
  def init_vm(
        bytecode,
        {address, caller, coinbase, difficulty, number, timestamp, origin, caller, value} = input
      ) do
    code_bin = bytecode_to_bin(bytecode)

    state = %{
      :stack => [],
      :memory => %{},
      :storage => %{},
      :code => code_bin,
      :cp => 0,
      :jumpdests => [],
      :address => address,
      :caller => caller,
      :coinbase => coinbase,
      :difficulty => difficulty,
      :number => number,
      :timestamp => timestamp,
      :origin => origin,
      :caller => caller,
      :value => value
    }
  end

  def set_stack(stack, state) do
    Map.put(state, :stack, stack)
  end

  def set_memory(memory, state) do
    Map.put(state, :memory, memory)
  end

  def set_storage(storage, state) do
    Map.put(state, :storage, storage)
  end

  def set_cp(cp, state) do
    Map.put(state, :cp, cp)
  end

  def inc_cp(state) do
    cp = Map.get(state, :cp)
    Map.put(state, :cp, cp + 1)
  end

  def add_jumpdest(jumpdest, state) do
    jumpdests = jumpdests(state)
    jumpdests1 = [jumpdest | jumpdests]
    Map.put(state, :jumpdests, jumpdests1)
  end

  def stack(state) do
    Map.get(state, :stack)
  end

  def memory(state) do
    Map.get(state, :memory)
  end

  def storage(state) do
    Map.get(state, :storage)
  end

  def code(state) do
    Map.get(state, :code)
  end

  def cp(state) do
    Map.get(state, :cp)
  end

  def jumpdests(state) do
    Map.get(state, :jumpdests)
  end

  def address(state) do
    Map.get(state, :address)
  end

  def caller(state) do
    Map.get(state, :caller)
  end

  def coinbase(state) do
    Map.get(state, :coinbase)
  end

  def difficulty(state) do
    Map.get(state, :difficulty)
  end

  def number(state) do
    Map.get(state, :number)
  end

  def timestamp(state) do
    Map.get(state, :timestamp)
  end

  def origin(state) do
    Map.get(state, :origin)
  end

  def caller(state) do
    Map.get(state, :caller)
  end

  def value(state) do
    Map.get(state, :value)
  end

  defp bytecode_to_bin(bytecode) do
    bytecode
    |> String.to_charlist()
    |> Enum.chunk_every(2)
    |> Enum.reduce([], fn x, acc ->
      {code, _} = x |> List.to_string() |> Integer.parse(16)

      [code | acc]
    end)
    |> Enum.reverse()
    |> Enum.reduce(<<>>, fn x, acc ->
      acc <> <<x::size(8)>>
    end)
  end
end
