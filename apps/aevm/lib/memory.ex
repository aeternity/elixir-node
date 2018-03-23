defmodule Memory do
  use Bitwise

  def store(address, value, memory) do
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

  def store8(address, value, memory) do
    memory_index = trunc(Float.floor(address / 32) * 32)
    position = rem(address, 32)
    prev_bits = position * 8
    size_bits = 8

    saved_value = Map.get(memory, memory_index, 0)

    <<prev::size(prev_bits), _::size(size_bits), next::binary>> = <<saved_value::256>>
    value_binary = <<value::size(size_bits)>>
    new_value_binary = <<prev::size(prev_bits)>> <> value_binary <> next
    <<new_value::256>> = new_value_binary

    Map.put(memory, memory_index, new_value)
  end
end
