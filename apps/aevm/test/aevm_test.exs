defmodule AevmTest do
  use ExUnit.Case
  doctest Aevm

  test "greets the world" do
    assert Aevm.hello() == :world
  end
end
