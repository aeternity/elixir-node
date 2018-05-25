defmodule AecoreCuckooTest do
  @moduledoc """
  Unit tests for the cuckoo module
  """

  require Logger

  use ExUnit.Case

  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Pow.Cuckoo
  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Tx.SpendTx

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
      323_238,
      336_565,
      356_430,
      356_664,
      396_665,
      31_313_936,
      31_623_338,
      32_306_366,
      32_316_364,
      32_356_130,
      32_396_562,
      32_613_366,
      32_623_363,
      32_646_635,
      33_343_462,
      33_343_764,
      33_346_531,
      33_353_836,
      33_356_435,
      33_376_633,
      33_396_166,
      33_613_064,
      33_636_234,
      33_653_561,
      33_663_038,
      34_616_234,
      34_663_134,
      35_383_763,
      35_616_262,
      35_623_738,
      35_656_530,
      36_333_262,
      36_636_462,
      36_643_738,
      36_653_264,
      36_656_366,
      36_656_535,
      37_323_638,
      37_373_563,
      37_376_539,
      37_383_934,
      37_663_733
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
      <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236, 181,
        172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>

    %Block{
      header: %Header{
        height: 5,
        nonce: 35,
        pow_evidence: List.duplicate(0, 42),
        prev_hash: prev_hash,
        root_hash: root_hash,
        target: 553_713_663,
        height: 6,
        nonce: 218,
        pow_evidence: nil,
        prev_hash: prev_hash,
        time: 1_523_540_274_221,
        txs_hash: txs_hash,
        miner: miner,
        version: 1
      },
      txs: []
    }
  end
end
