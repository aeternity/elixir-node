defmodule HashcashTest do
  use ExUnit.Case
  doctest Aecore.Pow.Hashcash

  alias Aecore.Pow.Hashcash
  alias Aecore.Structures.Block

  @tag timeout: 10000000
  test "successfull test" do
    assert {:ok, mined_header} = Hashcash.generate(Block.genesis_block.header)
    assert :true = Hashcash.verify(mined_header)
  end
end
