defmodule HashcashTest do
  use ExUnit.Case
  doctest Aecore.Pow.Hashcash

  alias Aecore.Pow.Hashcash
  alias Aecore.Block.Headers
  alias Aecore.Block.Genesis

  @tag timeout: 10000000
  test "successfull test" do
    block = Genesis.genesis_block
    difficulty = Headers.difficulty(block.header)
    assert {:ok, nonce} = Hashcash.generate(block, difficulty)
    assert :true = Hashcash.verify(block, nonce, difficulty)
  end
end
