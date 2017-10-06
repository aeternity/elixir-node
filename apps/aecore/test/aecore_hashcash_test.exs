defmodule HashcashTest do
  use ExUnit.Case
  doctest Aecore.Pow.Hashcash

  alias Aecore.Pow.Hashcash
  alias Aecore.Block.Genesis

  @tag timeout: 10000000
  test "successfull test" do
    block = Genesis.genesis_block
    assert {:ok, new_block_header} = Hashcash.generate(block.header)
    assert :true = Hashcash.verify(new_block_header)
  end
end
