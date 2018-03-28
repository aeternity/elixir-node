defmodule Memory do
  use Bitwise

  def load(address, state) do
    memory = State.memory(state)
    {memory_index, bit_position} = get_index_in_memory(address)

    prev_saved_value = Map.get(memory, memory_index, 0)
    next_saved_value = Map.get(memory, memory_index + 32, 0)

    <<_::size(bit_position), prev::binary>> = <<prev_saved_value::256>>
    <<next::size(bit_position), _::binary>> = <<next_saved_value::256>>

    value_binary = prev <> <<next::size(bit_position)>>
    binary_word_to_integer(value_binary)
  end

  def store(address, value, state) do
    memory = State.memory(state)
    {memory_index, bit_position} = get_index_in_memory(address)
    remaining_bits = 256 - bit_position

    <<prev_bits::size(remaining_bits), next_bits::binary>> = <<value::256>>

    prev_saved_value = Map.get(memory, memory_index, 0)
    next_saved_value = Map.get(memory, memory_index + 32, 0)

    new_prev_value =
      write_part(
        bit_position,
        <<prev_bits::size(remaining_bits)>>,
        remaining_bits,
        <<prev_saved_value::256>>
      )

    new_next_value = write_part(0, next_bits, bit_position, <<next_saved_value::256>>)

    memory1 = Map.put(memory, memory_index, binary_word_to_integer(new_prev_value))
    memory2 = Map.put(memory1, memory_index + 32, binary_word_to_integer(new_next_value))

    State.set_memory(memory2, state)
  end

  def store8(address, value, state) do
    memory = State.memory(state)
    {memory_index, bit_position} = get_index_in_memory(address)

    saved_value = Map.get(memory, memory_index, 0)

    new_value = write_part(bit_position, <<value::size(8)>>, 8, <<saved_value::256>>)

    memory1 = Map.put(memory, memory_index, binary_word_to_integer(new_value))

    State.set_memory(memory1, state)
  end

  def memory_size(state) do
    memory = State.memory(state)
    memory |> Map.keys() |> Enum.sort() |> Enum.at(-1)
  end

  defp get_index_in_memory(address) do
    memory_index = trunc(Float.floor(address / 32) * 32)
    bit_position = rem(address, 32) * 8

    {memory_index, bit_position}
  end

  defp write_part(bit_position, value_binary, size_bits, chunk_binary) do
    <<prev::size(bit_position), _::size(size_bits), next::binary>> = chunk_binary
    <<prev::size(bit_position)>> <> value_binary <> next
  end

  defp binary_word_to_integer(word) do
    <<word_integer::size(256)>> = word

    word_integer
  end
end
