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
      333_836,
      336_535,
      336_566,
      636_431,
      653_662,
      31_303_631,
      31_323_337,
      31_323_533,
      31_376_434,
      31_613_636,
      31_646_335,
      31_653_664,
      32_303_633,
      32_313_562,
      32_313_833,
      32_373_361,
      32_616_131,
      33_306_230,
      33_336_138,
      34_306_431,
      34_363_566,
      34_613_063,
      34_633_630,
      35_323_139,
      35_326_266,
      35_333_838,
      35_353_632,
      35_613_935,
      35_626_530,
      35_636_166,
      35_666_664,
      36_373_735,
      36_383_266,
      37_313_431,
      37_323_364,
      37_323_962,
      37_333_561,
      37_353_034,
      37_353_334,
      37_623_537,
      37_623_631,
      37_636_664
    ]
  end

  defp block_candidate do
    root_hash =
      <<80, 183, 124, 144, 27, 153, 79, 165, 247, 186, 155, 60, 231, 172, 68, 154, 190, 179, 211,
        242, 161, 31, 105, 131, 3, 110, 51, 130, 119, 182, 175, 162>>

    prev_hash =
      <<67, 26, 173, 55, 192, 64, 54, 228, 222, 232, 254, 88, 20, 121, 71, 38, 66, 99, 244, 108,
        219, 114, 147, 87, 227, 254, 213, 186, 59, 143, 44, 71>>

    txs_hash =
      <<74, 150, 19, 89, 11, 237, 10, 76, 153, 248, 87, 163, 167, 2, 104, 0, 59, 128, 242, 179,
        223, 64, 76, 221, 239, 179, 216, 254, 133, 213, 19, 93>>

    receiver =
      <<2, 115, 12, 7, 179, 184, 232, 77, 47, 138, 178, 181, 104, 17, 206, 57, 232, 178, 17, 173,
        147, 30, 10, 205, 89, 37, 167, 213, 199, 157, 121, 165, 215>>

    %Block{
      header: %Header{
        root_hash: root_hash,
        target: 553_713_663,
        height: 6,
        nonce: 78,
        pow_evidence: nil,
        prev_hash: prev_hash,
        time: 1_523_540_274_221,
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
