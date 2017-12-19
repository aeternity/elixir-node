defmodule AernoldTest do
  use ExUnit.Case
  doctest Aernold

  test "greets the world" do
    assert Aernold.hello() == :world
  end
end
