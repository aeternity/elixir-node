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
  alias Aecore.Structures.CoinbaseTx

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
      3437,
      326_361,
      393_563,
      393_632,
      393_636,
      613_264,
      623_037,
      623_836,
      31_306_464,
      31_313_030,
      31_343_039,
      31_633_865,
      32_323_136,
      32_353_132,
      32_366_139,
      32_636_466,
      32_643_937,
      33_323_062,
      33_343_134,
      33_373_864,
      33_383_263,
      34_313_135,
      34_326_663,
      34_356_661,
      34_373_836,
      34_646_135,
      35_303_738,
      35_333_537,
      35_333_733,
      35_346_464,
      35_393_936,
      35_653_833,
      35_666_164,
      36_356_364,
      36_623_761,
      36_646_632,
      37_363_361,
      37_363_930,
      37_373_137,
      37_383_066,
      37_626_163,
      37_663_039
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

    receiver =
      <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236, 181,
        172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>

    %Block{
      header: %Header{
        height: 5,
        nonce: 21,
        pow_evidence: List.duplicate(0, 42),
        prev_hash: prev_hash,
        root_hash: root_hash,
        target: 553_713_663,
        time: 1_525_437_886_361,
        txs_hash: txs_hash,
        version: 1
      },
      txs: [
        %SignedTx{
          data: %DataTx{
            fee: 0,
            nonce: 0,
            payload: %SpendTx{
              amount: 100,
              receiver: receiver,
              version: 1,
              payload: <<"payload">>
            },
            senders: [],
            type: SpendTx
          },
          signatures: []
        }
      ]
    }
  end
end
