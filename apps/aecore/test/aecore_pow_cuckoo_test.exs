defmodule AecoreCuckooTest do
  @moduledoc """
  Unit tests for the cuckoo module
  """

  require Logger

  use ExUnit.Case

  alias Aecore.Pow.Cuckoo
  alias Aecore.Chain.{Block, Header}

  @tag timeout: 60_000
  @tag :cuckoo
  test "Generate solution with a winning nonce and high target threshold" do
    {:ok, %{pow_evidence: found_solution}} = Cuckoo.generate(block_candidate().header)
    assert found_solution == wining_solution()
  end

  @tag timeout: 60_000
  @tag :cuckoo
  test "Verify solution with a high target threshold" do
    {:ok, header} = Cuckoo.generate(block_candidate().header)
    assert true == Cuckoo.verify(header)
  end

  defp wining_solution do
    [
      86,
      747,
      1166,
      1755,
      4270,
      4805,
      5174,
      5532,
      5871,
      5963,
      6096,
      6366,
      8883,
      9450,
      10_312,
      12_294,
      12_816,
      13_171,
      15_456,
      16_993,
      17_023,
      17_472,
      17_783,
      18_610,
      18_798,
      18_804,
      18_952,
      19_922,
      20_024,
      20_539,
      23_058,
      23_252,
      23_966,
      24_242,
      24_292,
      24_670,
      25_259,
      31_331,
      31_400,
      31_521,
      32_066,
      32_468
    ]
  end

  defp block_candidate do
    root_hash =
      <<3, 182, 90, 114, 176, 76, 149, 119, 61, 31, 182, 67, 236, 226, 55, 252, 162, 181, 135, 38,
        5, 100, 44, 42, 98, 30, 168, 89, 51, 12, 94, 36>>

    prev_hash =
      <<12, 191, 206, 141, 4, 69, 187, 23, 135, 251, 168, 240, 201, 114, 223, 101, 113, 237, 36,
        91, 38, 191, 166, 21, 145, 170, 182, 194, 136, 25, 12, 248>>

    txs_hash =
      <<34, 12, 151, 127, 24, 49, 178, 171, 232, 129, 182, 150, 150, 82, 125, 117, 238, 56, 140,
        96, 82, 104, 183, 188, 198, 161, 158, 118, 132, 90, 208, 8>>

    miner =
      <<247, 211, 181, 238, 250, 50, 77, 72, 54, 240, 138, 145, 150, 67, 155, 78, 4, 209, 161,
        215, 60, 235, 172, 17, 79, 7, 166, 47, 245, 208, 58, 225>>

    %Block{
      header: %Header{
        height: 5,
        nonce: 127,
        pow_evidence: List.duplicate(0, 42),
        prev_hash: prev_hash,
        root_hash: root_hash,
        target: 553_713_663,
        time: 1_523_540_274_221,
        txs_hash: txs_hash,
        miner: miner,
        version: 1
      },
      txs: []
    }
  end
end
