defmodule Memory do

  def write(address, value, size, memory) do
    bit_list = to_sized_bit_list(value, size)
    memory_size = Enum.count(memory)

    memory1 =
      if address > memory_size do
        extend(memory, address - memory_size)
        memory ++ bit_list
      else
        left = Enum.slice(memory, 0, address)
        right = Enum.drop(memory, address + size)
        left ++ bit_list ++ right
      end
  end

  def extend(memory, size) do
    fill = Enum.map(1..size, fn _ -> 0 end)
    memory ++ fill
  end

  def to_sized_bit_list(number, size) do
    bit_list = to_bit_list(number)
    bit_list_count = Enum.count(bit_list)
    cond do
        bit_list_count < size ->
          fill_count = size - bit_list_count
          fill_with = Enum.map(1..fill_count, fn _ -> 0 end)
          fill_with ++ bit_list

        bit_list_count > size ->
          remove_count = bit_list_count - size
          Enum.drop(bit_list, remove_count)

        true ->
          bit_list
      end
  end

  def to_bit_list(number) do
    number
    |> Integer.to_string(2)
    |> String.split("")
    |> List.delete_at(0)
    |> List.delete_at(-1)
    |> Enum.reduce([], fn(x, acc) ->
          {x_int, _} = Integer.parse(x)

          [x_int | acc]
       end)
    |> Enum.reverse()
  end

end
