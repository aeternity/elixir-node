defmodule MultiNodeSyncTest do
  use ExUnit.Case
  @tag timeout: 180000

  test "run second node" do
    System.cmd("cp", ["-R", "../../../elixir-node", "../../../elixir-node2"])
    System.cmd "rm", ["-rf", "../../../elixir-node2/apps/aecore/test/"]
    System.cmd "rm", ["../../../elixir-node2/apps/aehttpclient/test/aehttpclient_test.exs"]
    System.cmd "sed", ["-i", "s/4000/4001/", "../../../elixir-node2/apps/aehttpserver/config/dev.exs"]
    System.cmd "sed", ["-i", "s/4000/4001/", "../../../elixir-node2/apps/aehttpserver/config/test.exs"]

    System.cmd "mix", ["test"], cd: "../../../elixir-node2", into: IO.stream(:stdio, :line)
    System.cmd "rm", ["-rf", "../../../elixir-node2"]
  end
end
