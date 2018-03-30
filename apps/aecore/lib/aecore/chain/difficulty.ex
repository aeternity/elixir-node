defmodule Aecore.Chain.Difficulty do
  @moduledoc """
  Contains functions used to calculate the PoW difficulty.
  """

  alias Aecore.Structures.Block
  alias Aeutil.Scientific

  use Bitwise

  @number_of_blocks 10
  @highest_target_scientific 0x2100FFFF
  @expected_mine_rate 30_000

  def get_number_of_blocks do
    @number_of_blocks
  end

  @spec calculate_next_difficulty(integer(), list(Block.t())) :: integer()
  def calculate_next_difficulty(timestamp, previous_blocks) do
    sorted_blocks =
      Enum.sort(previous_blocks, fn block1, block2 ->
        block1.header.height < block2.header.height
      end)

    k = Scientific.scientific_to_integer(@highest_target_scientific) * bsl(1, 32)

    k_div_targets =
      for block <- sorted_blocks do
        div(k, Scientific.scientific_to_integer(block.header.target))
      end

    sum_k_div_targets = Enum.sum(k_div_targets)
    last_block = hd(sorted_blocks)
    total_time = calculate_distance(last_block, timestamp)
    new_target_int = div(total_time * k, @expected_mine_rate * sum_k_div_targets)
    min(@highest_target_scientific, Scientific.integer_to_scientific(new_target_int))
  end

  @spec calculate_distance(Block.t(), integer()) :: float()
  defp calculate_distance(last_block, timestamp) do
    max(1, timestamp - last_block.header.time)
  end
end
