defmodule AecorePowMockTest do
  @moduledoc """
  Unit tests for the mock miner module
  """

  require Logger

  use ExUnit.Case

  alias Aecore.Pow.Mock
  alias Aecore.Chain.Header

  @tag :mock_miner
  test "Generate solution and test it validates" do
    {:ok, valid_header} = Mock.generate(header_candidate())
    assert Mock.verify(valid_header)
  end

  @tag :mock_miner
  test "Vefify empty invalid solution fails" do
    assert false == Mock.verify(header_candidate())
  end

  defp header_candidate do
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

    %Header{
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
    }
  end
end
