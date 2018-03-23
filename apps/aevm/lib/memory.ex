defmodule Memory do
  use Bitwise

  def write(address, value, size, memory) do
    memory_index = trunc(Float.floor(address / 32) * 32)
    next = rem(address, 32) * 8
    prev = 256 - next

    prev_saved_value = Map.get(memory, memory_index, 0)
    next_saved_value = Map.get(memory, memory_index + 32, 0)

    <<prev_bits::size(prev), next_bits::binary>> = <<value::256>>
    <<prev_saved_bits::size(next), _::binary>> = <<prev_saved_value::256>>
    <<_::size(next), next_saved_bits::binary>> = <<next_saved_value::256>>

    <<prev_value::size(256)>> = <<prev_saved_bits::size(next)>> <> <<prev_bits::size(prev)>>
    <<next_value::size(256)>> = next_bits <> next_saved_bits

    memory1 = Map.put(memory, memory_index, prev_value)
    Map.put(memory1, memory_index + 32, next_value)
  end
end
