defmodule HashcashTest do
  use ExUnit.Case
  doctest Aecore.Pow.Hashcash

  # alias Aecore.Pow.Hashcash
  # alias Aecore.Chain.Header
  # alias Aecore.Chain.Block
  # alias Aecore.Chain.Genesis

  # @tag timeout: 10000000
  # test "successfull test" do
  #  header =
  #    %Header{
  #      height: 0,
  #      prev_hash: <<0::256>>,
  #      txs_hash: <<0::256>>,
  #      root_hash: <<0 :: 256>>,
  #      time: 1_507_275_094_308,
  #      nonce: 19,
  #      version: Genesis.block().header.version,
  #      target: 1
  #    }
  #  start_nonce = 0
  #  assert {:ok, mined_header} = Hashcash.generate(header, start_nonce)
  #  assert :true = Hashcash.verify(mined_header)
  # end
end
