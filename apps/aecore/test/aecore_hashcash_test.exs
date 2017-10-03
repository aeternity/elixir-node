defmodule HashcashTest do
  use ExUnit.Case
  doctest Aecore.Pow.Hashcash

  alias Aecore.Pow.Hashcash

  @tag timeout: 10000000
  test "successfull test" do
    block = Aecore.Structures.Block.create
    difficulty  = block.header.difficulty_target
    assert {:ok, nonce} = Hashcash.generate(block, difficulty)
    assert :true = Hashcash.verify(block, nonce, difficulty)
  end
end
