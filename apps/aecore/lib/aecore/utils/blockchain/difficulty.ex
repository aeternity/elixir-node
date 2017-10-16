defmodule Aecore.Utils.Blockchain.Difficulty do

  alias Aecore.Chain.Worker, as: Chain

  @number_of_blocks 100
  @max_difficulty_change 2
  @target_distance 60000

  def get_number_of_blocks() do
    @number_of_blocks
  end

  @spec calculate_next_difficulty :: term()
  def calculate_next_difficulty() do
      Chain.get_blocks_for_difficulty_calculation
      |> calculate_next_difficulty()
  end

  @spec calculate_next_difficulty :: term()
  def calculate_next_difficulty(list) do
    [latest_block | _] = list
    if(length(list) == 1) do
      latest_block.header.difficulty_target
    else
      distance = calculate_distance(list)
      next_difficulty = latest_block.header.difficulty_target * (@target_distance / distance) |> Float.ceil() |> round()
      limit_max_difficulty_change(next_difficulty, latest_block.header.difficulty_target)
    end
  end

  @spec limit_max_difficulty_change(integer(), integer()) :: integer()
  def limit_max_difficulty_change(calculated_next_difficulty, last_difficult) do
    cond do
      (calculated_next_difficulty - last_difficult) > @max_difficulty_change ->
        last_difficult + @max_difficulty_change
      (last_difficult - calculated_next_difficulty) > @max_difficulty_change ->
        last_difficult - @max_difficulty_change
      true ->
        calculated_next_difficulty
    end
  end

  @spec calculate_distance(list) :: term()
  defp calculate_distance(list) do
    [head | tail] = list
    distances = List.foldl(tail, {head, []},
      fn(cur, {head, acc}) ->
        time_diff = head.header.timestamp - cur.header.timestamp
        {cur, acc ++ [time_diff]}
      end)

    sum = distances |> elem(1) |> Enum.sum
    sum / length(distances |> elem(1))
  end

end
