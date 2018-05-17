defmodule MultiNodeSyncTest do
  use ExUnit.Case

  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Worker, as: Chain
  @tag timeout: 180000

  setup do
    Peers.start_link([])
    Miner.start_link([])
    Chain.start_link([])
    []
  end

  test "run second node" do

    str = "defmodule MultiNodeSyncTest do
      use ExUnit.Case

      alias Aecore.Peers.Worker, as: Peers
      alias Aecore.Miner.Worker, as: Miner
      alias Aecore.Chain.Worker, as: Chain
      @tag timeout: 180000

      setup do
        Peers.start_link([])
        Miner.start_link([])
        Chain.start_link([])
        []
      end

      test \"run_sync\" do
        Peers.add_peer(\"localhost:4000\")
        :timer.sleep(5000)
        Miner.mine_sync_block_to_chain()
        :timer.sleep(5000)
        IO.puts \"Second node:\"
        IO.inspect Chain.top_block()
      end
    end"
    System.cmd("cp", ["-R", "../../../elixir-node", "../../../elixir-node2"])
    System.cmd "rm", ["-rf", "../../../elixir-node2/apps/aecore/test/"]
    System.cmd "mkdir", ["../../../elixir-node2/apps/aecore/test/"]
    System.cmd("cp", ["../../../elixir-node/apps/aecore/test/test_helper.exs", "../../../elixir-node2/apps/aecore/test/test_helper.exs"])
    System.cmd("cp", ["../../../elixir-node/apps/aecore/test/test_utils.ex", "../../../elixir-node2/apps/aecore/test/test_utils.ex"])
    {:ok, file} = File.open "../../../elixir-node2/apps/aecore/test/multi_node_sync_test.exs", [:write]
    IO.write(file, str)
    System.cmd "rm", ["../../../elixir-node2/apps/aehttpclient/test/aehttpclient_test.exs"]
    System.cmd "sed", ["-i", "s/4000/4002/", "../../../elixir-node2/apps/aehttpserver/config/dev.exs"]
    System.cmd "sed", ["-i", "s/4000/4002/", "../../../elixir-node2/apps/aehttpserver/config/test.exs"]

    Miner.mine_sync_block_to_chain
    System.cmd "mix", ["test"], cd: "../../../elixir-node2", into: IO.stream(:stdio, :line)
    IO.puts "First node:"
    IO.inspect Chain.top_block()
    System.cmd "rm", ["-rf", "../../../elixir-node2"]
  end


end
