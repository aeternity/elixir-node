defmodule Aecore.Governance.GovernanceConstants do
  @moduledoc """
  Aecore structure to provide governance constants.
  """

  @number_of_blocks_for_target_recalculation 10
  def number_of_blocks_for_target_recalculation, do: @number_of_blocks_for_target_recalculation

  @expected_mine_rate_ms 30_000
  def expected_mine_rate_ms, do: @expected_mine_rate_ms

  @coinbase_transaction_amount 100
  def coinbase_transaction_amount, do: @coinbase_transaction_amount
end
