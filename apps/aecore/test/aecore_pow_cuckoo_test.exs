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
      313_865,
      356_233,
      616_638,
      626_165,
      633_233,
      666_330,
      31_306_266,
      31_323_835,
      31_333_133,
      31_363_666,
      31_636_536,
      31_646_333,
      31_653_866,
      32_386_466,
      32_653_663,
      32_663_932,
      33_393_061,
      33_643_331,
      33_663_634,
      33_666_466,
      34_323_563,
      34_376_666,
      34_393_733,
      34_613_166,
      34_633_662,
      35_363_965,
      35_623_663,
      35_633_338,
      36_303_266,
      36_346_237,
      36_346_264,
      36_616_137,
      36_623_833,
      36_626_536,
      36_643_032,
      37_313_034,
      37_326_661,
      37_383_833,
      37_383_864,
      37_386_233,
      37_623_130,
      37_636_165
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
        nonce: 37,
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
