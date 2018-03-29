defmodule AecoreCuckooTest do
  require Logger
  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Pow.Cuckoo
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SpendTx

  @moduledoc """
  Unit tests for the cuckoo module
  """

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
    assert true = Cuckoo.verify(header)
  end

  defp wining_solution do
    [
      66,
      326_238,
      376_436,
      393_630,
      633_235,
      643_465,
      31_306_665,
      31_336_463,
      31_373_163,
      31_643_339,
      32_303_166,
      32_313_764,
      32_323_931,
      32_343_361,
      32_356_434,
      32_366_235,
      32_373_866,
      32_623_330,
      32_643_230,
      32_656_337,
      33_313_237,
      33_313_361,
      34_353_039,
      34_393_661,
      34_613_665,
      34_623_966,
      34_636_162,
      34_656_264,
      34_666_435,
      35_303_334,
      35_333_430,
      35_386_466,
      35_653_135,
      36_303_366,
      36_336_537,
      36_366_130,
      36_383_339,
      36_623_337,
      37_356_664,
      37_383_335,
      37_613_034,
      37_643_534
    ]
  end

  defp block_candidate do
    chain_state_hash =
      <<89, 106, 158, 113, 72, 135, 179, 65, 203, 213, 147, 3, 171, 5, 212, 247, 185, 71, 23, 75,
        92, 28, 157, 169, 104, 57, 137, 109, 101, 165, 68, 216>>

    prev_hash =
      <<218, 5, 20, 192, 102, 85, 30, 102, 146, 74, 65, 216, 173, 61, 211, 106, 226, 124, 64, 4,
        46, 233, 30, 88, 182, 202, 201, 110, 16, 250, 203, 168>>

    txs_hash =
      <<212, 247, 100, 110, 132, 78, 186, 43, 39, 94, 182, 84, 237, 241, 206, 65, 125, 234, 153,
        132, 62, 227, 240, 191, 52, 250, 138, 239, 116, 145, 186, 230>>

    to_acc =
      <<4, 189, 182, 95, 56, 124, 178, 175, 226, 223, 46, 184, 93, 2, 93, 202, 223, 118, 74, 222,
        92, 242, 192, 92, 157, 35, 13, 93, 231, 74, 52, 96, 19, 203, 81, 87, 85, 42, 30, 111, 104,
        8, 98, 177, 233, 236, 157, 118, 30, 223, 11, 32, 118, 9, 122, 57, 7, 143, 127, 1, 103,
        242, 116, 234, 47>>

    %Block{
      header: %Header{
        chain_state_hash: chain_state_hash,
        difficulty_target: 553_713_663,
        height: 1,
        nonce: 0,
        pow_evidence: nil,
        prev_hash: prev_hash,
        timestamp: 1_522_328_437_248,
        txs_hash: txs_hash,
        version: 1
      },
      txs: [
        %Aecore.Structures.SignedTx{
          data: %Aecore.Structures.DataTx{
            fee: 0,
            from_acc: nil,
            nonce: 0,
            payload: %Aecore.Structures.SpendTx{
              to_acc:
                <<2, 228, 151, 134, 45, 15, 55, 89, 25, 243, 122, 25, 30, 77, 199, 168, 21, 189,
                  240, 238, 169, 0, 105, 94, 225, 180, 57, 1, 180, 114, 52, 56, 1>>,
              value: 100
            },
            type: Aecore.Structures.SpendTx
          },
          signature: nil
        }
      ]
    }
  end
end
