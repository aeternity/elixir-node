defmodule HashcashTest do
  use ExUnit.Case
  doctest Aecore.Pow.Hashcash

  alias Aecore.Pow.Hashcash
  alias Aecore.Block.Genesis

  @tag timeout: 10000000
  test "successfull test" do
    assert {:ok, mined_header} = Hashcash.generate(Genesis.genesis_block.header)
    assert :true = Hashcash.verify(mined_header)
  end
end
