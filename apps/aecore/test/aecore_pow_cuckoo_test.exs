defmodule AecoreCuckooTest do
  require Logger
  use ExUnit.Case

  alias Aecore.Pow.Cuckoo
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header

  @moduledoc """
  Unit tests for the cuckoo module
  """
   @tag timeout: 10_000
   @tag :cuckoo
   test "Generate solution with a winning nonce and high target threshold" do
     %{pow_evidence: found_solution} = Cuckoo.generate(block_candidate().header)
     assert found_solution == wining_solution()
   end

   @tag timeout: 10_000
   @tag :cuckoo
   test "Verify solution with a high target threshold" do
     header = Cuckoo.generate(block_candidate().header)
     assert true = Cuckoo.verify(header)
   end

  defp wining_solution do
     [323_333, 333_635, 356_466, 636_139,
      646_165, 663_665, 663_739, 31_306_333,
      31_373_934, 31_376_265, 31_613_030, 31_633_064,
      31_636_339, 31_653_839, 32_303_738, 32_306_461,
      32_313_830, 32_323_733, 32_393_364, 32_396_234,
      33_323_435, 33_346_230, 33_616_139, 34_323_339,
      34_326_132, 34_326_539, 34_373_434, 34_643_263,
      35_316_335, 35_363_536, 35_626_131, 35_653_164,
      36_303_962, 36_323_737, 36_393_163, 36_666_663,
      37_336_636, 37_356_164, 37_626_237, 37_633_337,
      37_663_630, 37_666_439]
   end

  defp block_candidate do
    %Block{header: %Header{chain_state_hash:
                           <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0>>,
                           difficulty_target: 1, height: 0, nonce: 76,
                           pow_evidence: nil,
                           prev_hash: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0>>, timestamp: 1507275094308,
                           txs_hash: <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
                           0, 0>>, version: 1}, txs: []}
  end
end
