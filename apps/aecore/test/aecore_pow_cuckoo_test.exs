#  Broken PoW logics/tests/no idea what, should be fixed and only then uncommented/removed/replaced.

# defmodule AecoreCuckooTest do
#     @moduledoc """
#     Unit tests for the cuckoo module
#     """

#     require Logger

#     use ExUnit.Case

#     alias Aecore.Persistence.Worker, as: Persistence
#     alias Aecore.Pow.Cuckoo
#     alias Aecore.Chain.Block
#     alias Aecore.Chain.Header
#     alias Aecore.Tx.SignedTx
#     alias Aecore.Tx.DataTx
#     alias Aecore.Account.Tx.SpendTx

#     setup do
#       on_exit(fn ->
#         Persistence.delete_all_blocks()
#         :ok
#       end)
#     end
#  Broken PoW logics/tests/no idea what, should be fixed and only then uncommented/removed/replaced.

#     @tag timeout: 10_000
#     @tag :cuckoo
#     test "Generate solution with a winning nonce and high target threshold", setup do
#       %{pow_evidence: found_solution} = Cuckoo.generate(block_candidate().header)
#       assert found_solution == wining_solution()
#     end
#  Broken PoW logics/tests/no idea what, should be fixed and only then uncommented/removed/replaced.

#     @tag timeout: 10_000
#     @tag :cuckoo
#     test "Verify solution with a high target threshold", setup do
#       header = Cuckoo.generate(block_candidate().header)
#       assert true == Cuckoo.verify(header)
#     end

#     defp wining_solution do
#       [
#         313_161,
#         333_265,
#         343_834,
#         353_733,
#         31_303_962,
#         31_326_661,
#         31_633_262,
#         31_653_335,
#         32_306_536,
#         32_343_266,
#         32_623_632,
#         32_636_139,
#         32_643_033,
#         32_646_138,
#         33_303_562,
#         33_336_533,
#         33_363_363,
#         33_373_036,
#         33_623_564,
#         33_636_233,
#         34_323_432,
#         34_386_133,
#         34_396_535,
#         34_623_435,
#         34_623_931,
#         34_656_436,
#         35_333_130,
#         35_333_131,
#         35_346_566,
#         35_363_237,
#         35_366_532,
#         35_393_964,
#         36_356_432,
#         36_613_234,
#         36_613_339,
#         36_643_764,
#         37_316_566,
#         37_373_265,
#         37_396_363,
#         37_613_535,
#         37_643_435,
#         37_656_166
#       ]
#     end
#  Broken PoW logics/tests/no idea what, should be fixed and only then uncommented/removed/replaced.

#     defp block_candidate do
#       root_hash =
#         <<3, 182, 90, 114, 176, 76, 149, 119, 61, 31, 182, 67, 236, 226, 55, 252, 162, 181, 135, 38,
#           5, 100, 44, 42, 98, 30, 168, 89, 51, 12, 94, 36>>

#       prev_hash =
#         <<12, 191, 206, 141, 4, 69, 187, 23, 135, 251, 168, 240, 201, 114, 223, 101, 113, 237, 36,
#           91, 38, 191, 166, 21, 145, 170, 182, 194, 136, 25, 12, 248>>

#       txs_hash =
#         <<34, 12, 151, 127, 24, 49, 178, 171, 232, 129, 182, 150, 150, 82, 125, 117, 238, 56, 140,
#           96, 82, 104, 183, 188, 198, 161, 158, 118, 132, 90, 208, 8>>

#       miner =
#         <<3, 238, 194, 37, 53, 17, 131, 41, 32, 167, 209, 197, 236, 138, 35, 63, 33, 4, 236, 181,
#           172, 160, 156, 141, 129, 143, 104, 133, 128, 109, 199, 73, 102>>

#       %Block{
#         header: %Header{
#           height: 5,
#           nonce: 35,
#           pow_evidence: List.duplicate(0, 42),
#           prev_hash: prev_hash,
#           root_hash: root_hash,
#           target: 553_713_663,
#           height: 6,
#           nonce: 218,
#           pow_evidence: nil,
#           prev_hash: prev_hash,
#           time: 1_523_540_274_221,
#           txs_hash: txs_hash,
#           miner: miner,
#           version: 1
#         },
#         txs: []
#       }
#     end
#   end
#  Broken PoW logics/tests/no idea what, should be fixed and only then uncommented/removed/replaced.
