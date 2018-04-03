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
    assert true == Cuckoo.verify(header)
  end

  defp wining_solution do
    [
      6536,
      323_237,
      323_631,
      373_133,
      386_166,
      393_131,
      31_303_937,
      31_316_633,
      31_323_232,
      31_373_338,
      31_623_435,
      31_643_438,
      31_653_235,
      31_666_134,
      32_313_166,
      32_346_635,
      32_346_638,
      32_353_636,
      32_373_034,
      32_373_036,
      32_643_530,
      32_653_461,
      32_666_131,
      33_316_235,
      34_316_238,
      34_333_134,
      34_336_661,
      34_353_835,
      34_653_439,
      34_663_932,
      35_386_561,
      35_616_330,
      35_633_361,
      36_326_431,
      36_356_538,
      36_626_630,
      36_636_131,
      36_636_566,
      36_663_136,
      36_666_366,
      37_353_233,
      37_643_632
    ]
  end

  defp block_candidate do
    root_hash =
      <<230, 129, 113, 45, 47, 180, 171, 8, 15, 55, 74, 106, 150, 170, 190, 220, 32, 87, 30, 102,
        106, 67, 131, 247, 17, 56, 115, 147, 17, 115, 143, 196>>

    prev_hash =
      <<188, 84, 93, 222, 212, 45, 228, 224, 165, 111, 167, 218, 25, 31, 60, 159, 14, 163, 105,
        206, 162, 32, 65, 127, 128, 188, 162, 75, 124, 8, 229, 131>>

    txs_hash =
      <<170, 58, 122, 219, 147, 41, 59, 140, 28, 127, 153, 68, 245, 18, 205, 22, 147, 124, 157,
        182, 123, 24, 41, 71, 132, 6, 162, 20, 227, 255, 25, 25>>

    receiver =
      <<4, 189, 182, 95, 56, 124, 178, 175, 226, 223, 46, 184, 93, 2, 93, 202, 223, 118, 74, 222,
        92, 242, 192, 92, 157, 35, 13, 93, 231, 74, 52, 96, 19, 203, 81, 87, 85, 42, 30, 111, 104,
        8, 98, 177, 233, 236, 157, 118, 30, 223, 11, 32, 118, 9, 122, 57, 7, 143, 127, 1, 103,
        242, 116, 234, 47>>

    %Block{
      header: %Header{
        root_hash: root_hash,
        target: 1,
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
