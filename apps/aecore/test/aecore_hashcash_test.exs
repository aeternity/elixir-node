defmodule HashcashTest do
  use ExUnit.Case
  doctest Aecore.Pow.Hashcash

  alias Aecore.Pow.Hashcash
  alias Aecore.Structures.Block

  @tag timeout: 10000000
  test "successfull test" do
    start_nonce = 0
    assert {:ok, mined_header} = Hashcash.generate(Block.genesis_block.header, start_nonce)
    assert :true = Hashcash.verify(mined_header)
  end
end
