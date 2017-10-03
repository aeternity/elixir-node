defmodule Aecore.Structures.Difficulty do

  alias Aecore.Structures.Chain

  @number_of_blocks 100
  @target_distance 60000

  def calculate_next_difficulty() do
      blocks = Chain.all_blocks
      Enum.take(blocks, @number_of_blocks) |> calculate_next_difficulty()
  end

  def calculate_next_difficulty(list) do
    distance = calculate_distance(list)
    #TODO
  end

  defp calculate_distance(list) do
    [head | tail] = list
    distances = List.foldl(tail, {head, []}, fn(cur, {head, acc}) -> {cur, acc ++ [head.header.timestamp - cur.header.timestamp]} end)
    sum = distances |> elem(1) |> Enum.sum
    avg = sum / length(distances |> elem(1))
  end

end
