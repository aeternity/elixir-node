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
      346_438,
      356_235,
      643_639,
      663_435,
      31_303_130,
      31_303_835,
      31_386_664,
      31_616_537,
      31_626_561,
      31_656_262,
      32_343_834,
      32_356_330,
      32_363_338,
      32_386_462,
      33_303_638,
      33_353_733,
      33_376_562,
      33_633_335,
      33_643_437,
      34_353_864,
      34_363_363,
      34_393_031,
      34_623_364,
      34_636_530,
      35_333_936,
      35_346_366,
      35_363_263,
      35_363_637,
      35_376_463,
      35_376_561,
      35_386_230,
      35_613_265,
      35_626_139,
      35_633_935,
      36_316_166,
      36_366_633,
      36_383_230,
      36_616_232,
      36_626_232,
      37_393_839,
      37_633_732,
      37_646_539
    ]
  end

  defp block_candidate do
    chain_state_hash =
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
        chain_state_hash: chain_state_hash,
        difficulty_target: 1,
        height: 1,
        nonce: 31,
        pow_evidence: nil,
        prev_hash: prev_hash,
        timestamp: 1_518_427_070_317,
        txs_hash: txs_hash,
        version: 1
      },
      txs: [
        %SignedTx{
          data: %DataTx{
            type: SpendTx,
            payload: %{receiver: receiver, amount: 100, lock_time_block: 11},
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
