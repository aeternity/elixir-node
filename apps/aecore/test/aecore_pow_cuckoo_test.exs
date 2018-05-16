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
      313_431,
      326_232,
      366_662,
      376_433,
      31_343_834,
      31_353_565,
      31_353_763,
      31_373_166,
      31_636_662,
      32_313_135,
      32_336_139,
      32_343_438,
      32_363_730,
      32_653_665,
      33_306_662,
      34_303_664,
      34_313_565,
      34_316_161,
      34_346_366,
      34_356_663,
      34_373_037,
      34_376_436,
      34_376_636,
      34_396_238,
      34_633_731,
      35_313_435,
      35_326_235,
      35_336_332,
      35_623_035,
      35_633_833,
      35_653_530,
      36_326_362,
      36_326_562,
      36_353_462,
      36_363_630,
      36_383_364,
      36_626_333,
      37_303_930,
      37_383_436,
      37_396_665,
      37_613_937,
      37_643_937
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
        nonce: 121,
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
