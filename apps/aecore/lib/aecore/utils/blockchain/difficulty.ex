defmodule Aecore.Utils.Blockchain.Difficulty do

  alias Aecore.Structures.Chain

  @number_of_blocks 100
  @target_distance 60000

  @spec calculate_next_difficulty :: term()
  def calculate_next_difficulty() do
      blocks = Chain.all_blocks
      Enum.take(blocks, @number_of_blocks) |> calculate_next_difficulty()
  end

  @spec calculate_next_difficulty :: term()
  defp calculate_next_difficulty(list) do
    distance = calculate_distance(list)
    {latest_block | _} = list
    next_difficulty = latest_block.header.difficulty_target * (@target_distance / distance)
  end

  @spec calculate_distance :: term()
  defp calculate_distance(list) do
    [head | tail] = list
    distances = List.foldl(tail, {head, []},
      fn(cur, {head, acc}) ->
        {cur, acc ++ [head.header.timestamp - cur.header.timestamp]}
      end)
    sum = distances |> elem(1) |> Enum.sum
    avg = sum / length(distances |> elem(1))
  end

end
