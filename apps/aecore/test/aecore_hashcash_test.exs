defmodule HashcashTest do
  use ExUnit.Case
  doctest Aecore.Pow.Hashcash

  # alias Aecore.Pow.Hashcash
  # alias Aecore.Structures.Header
  # alias Aecore.Structures.Block

  # @tag timeout: 10000000
  # test "successfull test" do
  #  header =
  #    %Header{
  #      height: 0,
  #      prev_hash: <<0::256>>,
  #      txs_hash: <<0::256>>,
  #      chain_state_hash: <<0 :: 256>>,
  #      timestamp: 1_507_275_094_308,
  #      nonce: 19,
  #      version: Block.genesis_block().header.version,
  #      difficulty_target: 1
  #    }
  #  start_nonce = 0
  #  assert {:ok, mined_header} = Hashcash.generate(header, start_nonce)
  #  assert :true = Hashcash.verify(mined_header)
  # end
end
