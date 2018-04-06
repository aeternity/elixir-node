defmodule AecoreCuckooTest do
  @moduledoc """
  Unit tests for the cuckoo module
  """

  require Logger

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Pow.Cuckoo
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SpendTx

  setup do
    on_exit(fn ->
      Persistence.delete_all_blocks()
      :ok
    end)
  end

  @tag timeout: 10_000
  @tag :cuckoo
  test "Generate solution with a winning nonce and high target threshold", setup do
    %{pow_evidence: found_solution} = Cuckoo.generate(block_candidate().header)
    assert found_solution == wining_solution()
  end

  @tag timeout: 10_000
  @tag :cuckoo
  test "Verify solution with a high target threshold", setup do
    header = Cuckoo.generate(block_candidate().header)
    assert true == Cuckoo.verify(header)
  end

  defp wining_solution do
    [
      373_732,
      636_165,
      643_361,
      31_303_263,
      31_366_333,
      31_373_137,
      31_373_961,
      31_393_131,
      32_323_033,
      32_353_837,
      32_366_664,
      32_633_135,
      32_666_261,
      33_313_530,
      33_343_733,
      33_353_732,
      33_373_863,
      33_386_563,
      33_616_538,
      33_663_862,
      34_303_739,
      34_343_530,
      34_353_364,
      34_353_534,
      34_653_033,
      34_653_237,
      34_656_338,
      34_656_633,
      34_666_132,
      34_666_139,
      35_333_236,
      35_373_465,
      35_666_132,
      36_316_663,
      36_363_365,
      36_613_262,
      36_653_337,
      36_653_363,
      37_346_262,
      37_353_661,
      37_623_137,
      37_633_034
    ]
  end

  defp block_candidate do
    root_hash =
      <<89, 106, 158, 113, 72, 135, 179, 65, 203, 213, 147, 3, 171, 5, 212, 247, 185, 71, 23, 75,
        92, 28, 157, 169, 104, 57, 137, 109, 101, 165, 68, 216>>

    prev_hash =
      <<218, 5, 20, 192, 102, 85, 30, 102, 146, 74, 65, 216, 173, 61, 211, 106, 226, 124, 64, 4,
        46, 233, 30, 88, 182, 202, 201, 110, 16, 250, 203, 168>>

    txs_hash =
      <<212, 247, 100, 110, 132, 78, 186, 43, 39, 94, 182, 84, 237, 241, 206, 65, 125, 234, 153,
        132, 62, 227, 240, 191, 52, 250, 138, 239, 116, 145, 186, 230>>

    receiver =
      <<4, 189, 182, 95, 56, 124, 178, 175, 226, 223, 46, 184, 93, 2, 93, 202, 223, 118, 74, 222,
        92, 242, 192, 92, 157, 35, 13, 93, 231, 74, 52, 96, 19, 203, 81, 87, 85, 42, 30, 111, 104,
        8, 98, 177, 233, 236, 157, 118, 30, 223, 11, 32, 118, 9, 122, 57, 7, 143, 127, 1, 103,
        242, 116, 234, 47>>

    %Block{
      header: %Header{
        root_hash: root_hash,
        target: 553_713_663,
        height: 1,
        nonce: 72,
        pow_evidence: nil,
        prev_hash: prev_hash,
        time: 1_518_427_070_317,
        txs_hash: txs_hash,
        version: 1
      },
      txs: [
        %SignedTx{
          data: %DataTx{
            type: SpendTx,
            payload: %{receiver: receiver, amount: 100},
            fee: 0,
            sender: nil,
            nonce: 0
          },
          signature: nil
        }
      ]
    }
  end
end
