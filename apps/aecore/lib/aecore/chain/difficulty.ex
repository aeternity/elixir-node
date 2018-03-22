defmodule Aecore.Chain.Difficulty do
  alias Aecore.Structures.Block
  alias Aeutil.Scientific
  @number_of_blocks 10
  @max_difficulty_change Application.get_env(:aecore, :pow)[:max_difficulty_change]
  @target_distance 30_000

  def get_number_of_blocks() do
    @number_of_blocks
  end

  @spec calculate_next_difficulty(list(Block.t())) :: integer()
  def calculate_next_difficulty(list) do
    [latest_block | _] = list

    if length(list) == 1 do
      latest_block.header.difficulty_target
    else
      distance = calculate_distance(list)
      int_target = Scientific.scientific_to_integer(latest_block.header.difficulty_target)

      next_difficulty =
        (int_target * (@target_distance / distance))
        |> Float.ceil()
        |> round()

      limit_max_difficulty_change(next_difficulty, latest_block.header.difficulty_target)
    end
  end

  @spec limit_max_difficulty_change(integer(), integer()) :: integer()
  def limit_max_difficulty_change(calculated_next_difficulty, last_difficult) do
    int_last_difficult = Scientific.scientific_to_integer(last_difficult)

    cond do
      calculated_next_difficulty - int_last_difficult > @max_difficulty_change ->
        Scientific.integer_to_scientific(int_last_difficult + @max_difficulty_change)

      int_last_difficult - calculated_next_difficulty > @max_difficulty_change ->
        Scientific.integer_to_scientific(int_last_difficult - @max_difficulty_change)

      true ->
        Scientific.integer_to_scientific(calculated_next_difficulty)
    end
  end

  @spec calculate_distance(list(Block.t())) :: float()
  defp calculate_distance(list) do
    [head | tail] = list

    distances =
      List.foldl(tail, {head, []}, fn cur, {head, acc} ->
        time_diff = head.header.timestamp - cur.header.timestamp
        {cur, acc ++ [time_diff]}
      end)

    sum = distances |> elem(1) |> Enum.sum()
    sum / length(distances |> elem(1))
  end
end
