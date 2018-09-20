defmodule Aecore.Chain.Target do
  @moduledoc """
  Contains functions used to calculate the PoW difficulty.
  """

  alias Aecore.Chain.{Block, Header}
  alias Aecore.Governance.GovernanceConstants
  alias Aeutil.Scientific

  use Bitwise

  @highest_target_scientific 0x2100FFFF

  @spec highest_target_scientific :: non_neg_integer()
  def highest_target_scientific, do: @highest_target_scientific

  @spec calculate_next_target(integer(), list(Block.t())) :: integer()
  def calculate_next_target(timestamp, previous_blocks) do
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

    new_target_int =
      div(trunc(total_time * k), GovernanceConstants.expected_mine_rate_ms() * sum_k_div_targets)

    min(@highest_target_scientific, Scientific.integer_to_scientific(new_target_int))
  end

  @spec calculate_distance(Block.t(), integer()) :: float()
  defp calculate_distance(%Block{header: %Header{time: time}}, timestamp) do
    max(1, timestamp - time)
  end
end
