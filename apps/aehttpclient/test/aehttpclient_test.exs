defmodule AehttpclientTest do
  use ExUnit.Case
  doctest Aehttpclient

  test "greets the world" do
    assert Aehttpclient.hello() == :world
  end
end
