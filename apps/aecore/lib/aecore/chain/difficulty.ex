defmodule Aecore.Chain.Difficulty do
  @moduledoc """
  Contains functions used to calculate the PoW difficulty.
  """

  alias Aecore.Structures.Block

  @number_of_blocks 10
  @max_target_change Application.get_env(:aecore, :pow)[:max_target_change]
  @target_distance 30_000

  def get_number_of_blocks do
    @number_of_blocks
  end

  @spec calculate_next_target(list(Block.t())) :: non_neg_integer()
  def calculate_next_target(list) do
    [latest_block | _] = list

    if length(list) == 1 do
      latest_block.header.target
    else
      distance = calculate_distance(list)
      target = latest_block.header.target * (@target_distance / distance)

      next_target =
        target
        |> Float.ceil()
        |> round()

      limit_max_target_change(next_target, latest_block.header.target)
    end
  end

  @spec limit_max_target_change(non_neg_integer(), non_neg_integer()) :: non_neg_integer()
  def limit_max_target_change(calculated_next_target, last_target) do
    cond do
      calculated_next_target - last_target > @max_target_change ->
        last_target + @max_target_change

      last_target - calculated_next_target > @max_target_change ->
        last_target - @max_target_change

      true ->
        calculated_next_target
    end
  end

  @spec calculate_distance(list(Block.t())) :: float()
  defp calculate_distance(list) do
    [head | tail] = list

    distances =
      List.foldl(tail, {head, []}, fn cur, {head, acc} ->
        time_diff = head.header.time - cur.header.time
        {cur, acc ++ [time_diff]}
      end)

    sum = distances |> elem(1) |> Enum.sum()
    sum / length(distances |> elem(1))
  end
end
