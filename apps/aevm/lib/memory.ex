defmodule Memory do
  @moduledoc """
  Module for working with the VM's internal memory.

  The VM's internal memory is indexed (chunked) every 32 bytes,
  thus represented with a mapping between index and a 32-byte integer (word).

  Data from the memory can be accessed at byte level.
  """

  use Bitwise

  @chunk_size 32
  @word_size 256

  @doc """
  Read a word from the memory, starting at a given `address`.
  """
  @spec load(integer(), map()) :: {integer(), map()}
  def load(address, state) do
    memory = State.memory(state)
    {memory_index, bit_position} = get_index_in_memory(address)

    prev_saved_value = Map.get(memory, memory_index, 0)
    next_saved_value = Map.get(memory, memory_index + @chunk_size, 0)

    <<_::size(bit_position), prev::binary>> = <<prev_saved_value::256>>
    <<next::size(bit_position), _::binary>> = <<next_saved_value::256>>

    value_binary = prev <> <<next::size(bit_position)>>

    memory1 = update_memory_size(address + 31, memory)
    {binary_word_to_integer(value_binary), State.set_memory(memory1, state)}
  end

  @doc """
  Write a word (32 bytes) to the memory, starting at a given `address`
  """
  @spec store(integer(), integer(), map()) :: map()
  def store(address, value, state) do
    memory = State.memory(state)
    {memory_index, bit_position} = get_index_in_memory(address)
    remaining_bits = @word_size - bit_position

    <<prev_bits::size(remaining_bits), next_bits::binary>> = <<value::256>>

    prev_saved_value = Map.get(memory, memory_index, 0)

    new_prev_value =
      write_part(
        bit_position,
        <<prev_bits::size(remaining_bits)>>,
        remaining_bits,
        <<prev_saved_value::256>>
      )

    memory1 = Map.put(memory, memory_index, binary_word_to_integer(new_prev_value))

    memory2 =
      if rem(address, @chunk_size) != 0 do
        next_saved_value = Map.get(memory, memory_index + @chunk_size, 0)
        new_next_value = write_part(0, next_bits, bit_position, <<next_saved_value::256>>)
        Map.put(memory1, memory_index + @chunk_size, binary_word_to_integer(new_next_value))
      else
        memory1
      end

    memory3 = update_memory_size(address + 31, memory2)
    State.set_memory(memory3, state)
  end

  @doc """
  Write 1 byte to the memory, at a given `address`
  """
  @spec store8(integer(), integer(), map()) :: map()
  def store8(address, value, state) do
    memory = State.memory(state)
    {memory_index, bit_position} = get_index_in_memory(address)

    saved_value = Map.get(memory, memory_index, 0)

    new_value = write_part(bit_position, <<value::size(8)>>, 8, <<saved_value::256>>)

    memory1 = Map.put(memory, memory_index, binary_word_to_integer(new_value))

    memory2 = update_memory_size(address + 7, memory1)
    State.set_memory(memory2, state)
  end

  @doc """
  Get the current size of the memory, in chunks
  """
  @spec memory_size_words(map()) :: non_neg_integer()
  def memory_size_words(state) do
    memory = State.memory(state)
    Map.get(memory, :size)
  end

  @doc """
  Get the current size of the memory, in bytes
  """
  @spec memory_size_bytes(map()) :: non_neg_integer()
  def memory_size_bytes(state) do
    memory_size_words = memory_size_words(state)
    memory_size_words * @chunk_size
  end

  @doc """
  Get n bytes (area) from the memory, starting at a given address
  """
  @spec get_area(integer(), integer(), map()) :: {binary(), map()}
  def get_area(from, bytes, state) do
    memory = State.memory(state)

    {memory_index, bit_position} = get_index_in_memory(from)
    area = read(<<>>, bytes, bit_position, memory_index, memory)

    memory1 = update_memory_size(from + bytes - 1, memory)
    {area, State.set_memory(memory1, state)}
  end

  @doc """
  Write n bytes (area) to the memory, starting at a given address
  """
  @spec write_area(integer(), integer(), map()) :: map()
  def write_area(from, bytes, state) do
    memory = State.memory(state)

    {memory_index, bit_position} = get_index_in_memory(from)
    memory1 = write(bytes, bit_position, memory_index, memory)

    memory2 = update_memory_size(from + byte_size(bytes) - 1, memory1)
    State.set_memory(memory2, state)
  end

  # Read n bytes from the memory (may be bigger than 32 bytes),
  # starting at a given address in the memory

  defp read(read_value, 0, _bit_position, _memory_index, _memory) do
    read_value
  end

  defp read(read_value, bytes_left, bit_position, memory_index, memory) do
    memory_index_bits_left =
      if bit_position == 0 do
        @word_size
      else
        @word_size - bit_position
      end

    size_bits = bytes_left * 8

    bits_to_read =
      if memory_index_bits_left <= size_bits do
        memory_index_bits_left
      else
        size_bits
      end

    saved_value = Map.get(memory, memory_index, 0)

    <<_::size(bit_position), read_part::size(bits_to_read), _::binary>> = <<saved_value::256>>

    new_read_value = read_value <> <<read_part::size(bits_to_read)>>
    new_bytes_left = bytes_left - round(bits_to_read / 8)
    read(new_read_value, new_bytes_left, 0, memory_index + @chunk_size, memory)
  end

  # Write n bytes to the memory (may be bigger than 32 bytes),
  # starting at a given address in the memory

  defp write(<<>>, _bit_position, _memory_index, memory) do
    memory
  end

  defp write(bytes, bit_position, memory_index, memory) do
    memory_index_bits_left =
      if bit_position == 0 do
        @word_size
      else
        @word_size - bit_position
      end

    size_bits = byte_size(bytes) * 8

    bits_to_write =
      if memory_index_bits_left <= size_bits do
        memory_index_bits_left
      else
        size_bits
      end

    saved_value = Map.get(memory, memory_index, 0)

    <<new_bytes::size(bits_to_write), bytes_left::binary>> = bytes

    new_value_binary =
      write_part(
        bit_position,
        <<new_bytes::size(bits_to_write)>>,
        bits_to_write,
        <<saved_value::256>>
      )

    memory1 = Map.put(memory, memory_index, binary_word_to_integer(new_value_binary))

    write(bytes_left, 0, memory_index + @chunk_size, memory1)
  end

  # Get the index in memory, in which the `address` is positioned

  defp get_index_in_memory(address) do
    memory_index = trunc(Float.floor(address / @chunk_size) * @chunk_size)
    bit_position = rem(address, @chunk_size) * 8

    {memory_index, bit_position}
  end

  # Write given binary to a given memory chunk

  defp write_part(bit_position, value_binary, size_bits, chunk_binary) do
    <<prev::size(bit_position), _::size(size_bits), next::binary>> = chunk_binary
    <<prev::size(bit_position)>> <> value_binary <> next
  end

  # Get the integer value of a `word`

  defp binary_word_to_integer(word) do
    <<word_integer::size(256), _::binary>> = word

    word_integer
  end

  # Update the size of the memory, if the given `address` is positioned
  # outside of the biggest allocated chunk

  defp update_memory_size(address, memory) do
    {memory_index, _} = get_index_in_memory(address)
    current_mem_size_words = Map.get(memory, :size)

    if (memory_index + @chunk_size) / @chunk_size > current_mem_size_words do
      Map.put(memory, :size, round((memory_index + @chunk_size) / @chunk_size))
    else
      memory
    end
  end
end
