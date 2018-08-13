defmodule MultiNodeSyncTest do
  use ExUnit.Case

  alias Aetestframework.MultiNodeTestFramework.Worker, as: TestFramework
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Tx.Pool.Worker, as: Pool

  setup do
    TestFramework.start_link(%{})
    Chain.clear_state()
    Pool.get_and_empty_pool()

    # port1 = find_port(1)
    # TestFramework.new_node("node1", port1)
    # :timer.sleep 2000

    # port2 = find_port(port1 + 1)
    # TestFramework.new_node("node2", port2)
    # :timer.sleep 2000

    # port3 = find_port(port2 + 1)
    # TestFramework.new_node("node3", port3)
    # :timer.sleep 2000

    # port4 = find_port(port3 + 1)
    # TestFramework.new_node("node4", port4)
    # :timer.sleep 2000

    on_exit(fn ->
      Chain.clear_state()
      Pool.get_and_empty_pool()
      :ok
    end)
  end

  @tag :sync_test
  test "test" do
    IO.inspect path = String.replace(System.cwd(), ~r/(?<=elixir-node).*$/, "")
    IO.inspect :os.cmd('lsof -i -n -P')
    IO.inspect process_port = Port.open({:spawn, "make iex-3"}, [:binary, cd: path])
  end

  # @tag :sync_test
  # test "spend_tx test" do
  #   TestFramework.sync_two_nodes("node1", "node2")

  #   TestFramework.sync_two_nodes("node2", "node3")

  #   TestFramework.sync_two_nodes("node3", "node4")

  #   TestFramework.mine_sync_block("node1")
  #   TestFramework.spend_tx("node1")
  #   TestFramework.mine_sync_block("node1")

  #   TestFramework.get_node_top_block_hash("node1")

  #   TestFramework.get_node_top_block_hash("node4")

  #   assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node4")

  #   TestFramework.delete_all_nodes()
  # end

  # @tag :sync_test
  # @tag timeout: 100_000
  # test "oracles test" do
  #   TestFramework.sync_two_nodes("node1", "node2")

  #   TestFramework.sync_two_nodes("node2", "node3")

  #   TestFramework.sync_two_nodes("node3", "node4")

  #   TestFramework.mine_sync_block("node2")
  #   TestFramework.register_oracle("node2")
  #   TestFramework.mine_sync_block("node2")

  #   TestFramework.extend_oracle("node2")
  #   TestFramework.mine_sync_block("node2")

  #   TestFramework.mine_sync_block("node4")
  #   TestFramework.query_oracle("node4")
  #   TestFramework.mine_sync_block("node4")

  #   TestFramework.mine_sync_block("node2")
  #   TestFramework.respond_oracle("node2")
  #   TestFramework.mine_sync_block("node2")

  #   TestFramework.get_node_top_block_hash("node1")

  #   TestFramework.get_node_top_block_hash("node4")

  #   assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node4")

  #   TestFramework.delete_all_nodes()
  # end

  # @tag :sync_test
  # @tag timeout: 100_000
  # test "namings test" do
  #   TestFramework.sync_two_nodes("node1", "node2")

  #   TestFramework.sync_two_nodes("node2", "node3")

  #   TestFramework.sync_two_nodes("node3", "node4")

  #   TestFramework.mine_sync_block("node2")
  #   TestFramework.naming_pre_claim("node2")
  #   TestFramework.mine_sync_block("node2")

  #   TestFramework.naming_claim("node2")
  #   TestFramework.mine_sync_block("node2")

  #   TestFramework.mine_sync_block("node2")
  #   TestFramework.naming_update("node2")
  #   TestFramework.mine_sync_block("node1")

  #   TestFramework.mine_sync_block("node2")
  #   TestFramework.naming_transfer("node2")
  #   TestFramework.mine_sync_block("node2")

  #   TestFramework.mine_sync_block("node2")
  #   TestFramework.naming_revoke("node2")
  #   TestFramework.mine_sync_block("node2")

  #   TestFramework.get_node_top_block_hash("node1")

  #   TestFramework.get_node_top_block_hash("node4")

  #   assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node4")

  #   TestFramework.delete_all_nodes()
  # end

  # @tag :sync_test
  # test "balance test" do
  #   TestFramework.sync_two_nodes("node1", "node2")

  #   TestFramework.sync_two_nodes("node2", "node3")

  #   TestFramework.sync_two_nodes("node3", "node4")

  #   TestFramework.update_pubkeys_state()

  #   TestFramework.mine_sync_block("node1")
  #   TestFramework.mine_sync_block("node1")
  #   TestFramework.send_tokens("node1", "node3", 50)
  #   TestFramework.mine_sync_block("node1")

  #   TestFramework.send_tokens("node3", "node2", 20)
  #   TestFramework.mine_sync_block("node3")
  #   TestFramework.send_tokens("node2", "node4", 10)
  #   TestFramework.mine_sync_block("node2")

  #   TestFramework.update_balance("node1")

  #   TestFramework.update_balance("node2")

  #   TestFramework.update_balance("node3")

  #   TestFramework.update_balance("node4")

  #   assert TestFramework.get_balance("node4") == 10

  #   TestFramework.delete_all_nodes()
  # end

  def find_port(start_port) do
    if TestFramework.busy_port?("300#{start_port}") ||
         TestFramework.busy_port?("400#{start_port}") do
      find_port(start_port + 1)
    else
      start_port
    end
  end
end
