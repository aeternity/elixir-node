defmodule AecoreCuckooTest do
  require Logger
  use ExUnit.Case, async: false

  #alias Aecore.Pow.Cuckoo
  #alias Aecore.Structures.Block

  @moduledoc """
  Unit tests for the cuckoo module
  """
  # @tag timeout: 1_000_000_000
  # @tag :cuckoo
  # test "Generate with a winning nonce and high target threshold, verify it" do
  #   block_header = %{Block.genesis_block().header | pow_evidence: nil}
  #   {t1, res}  =
  #     :timer.tc(Cuckoo, :generate,
  #       [block_header])
  #   Logger.info("Generated in #{t1} microsecs")
  #   assert :ok =  :erlang.element(1, res)
  #   {:ok, new_block_header} = res

  #   ## verify the solution
  #   {t2, res2} =
  #     :timer.tc(Cuckoo, :verify, [new_block_header])
  #   Logger.info("Verified in #{t2} microsecs")
  #   assert true = res2
  # end

end
