defmodule MultiNodeSyncTest do
  use ExUnit.Case

  alias Aetestframework.MultiNodeTestFramework.Worker, as: TestFramework
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Tx.Pool.Worker, as: Pool

  setup do
    TestFramework.start_link(%{})
    Chain.clear_state()
    Pool.get_and_empty_pool()
    port1 = find_port(1)
    TestFramework.new_node("node1", port1)
    :timer.sleep 2000

    port2 = find_port(port1 + 1)
    TestFramework.new_node("node2", port2)
    :timer.sleep 2000

    port3 = find_port(port2 + 1)
    TestFramework.new_node("node3", port3)
    :timer.sleep 2000

    port4 = find_port(port3 + 1)
    TestFramework.new_node("node4", port4)
    :timer.sleep 2000

    on_exit(fn ->
      Chain.clear_state()
      Pool.get_and_empty_pool()
      :ok
    end)
  end

  @tag :sync_test
  test "spend_tx test" do
    TestFramework.sync_two_nodes("node1", "node2")

    TestFramework.sync_two_nodes("node2", "node3")

    TestFramework.sync_two_nodes("node3", "node4")

    TestFramework.mine_sync_block("node1")
    TestFramework.spend_tx("node1")
    TestFramework.mine_sync_block("node1")

    TestFramework.get_node_top_block_hash("node1")

    TestFramework.get_node_top_block_hash("node4")

    :timer.sleep(2000)

    assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node4")
    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  test "oracles test" do
    TestFramework.sync_two_nodes("node1", "node2")

    TestFramework.sync_two_nodes("node2", "node3")

    TestFramework.sync_two_nodes("node3", "node4")

    TestFramework.mine_sync_block("node2")
    TestFramework.register_oracle("node2")
    TestFramework.mine_sync_block("node2")

    # :timer.sleep 3000

    TestFramework.extend_oracle("node2")
    TestFramework.mine_sync_block("node2")

    TestFramework.mine_sync_block("node4")
    TestFramework.query_oracle("node4")
    TestFramework.mine_sync_block("node4")

    TestFramework.mine_sync_block("node2")
    TestFramework.respond_oracle("node2")
    TestFramework.mine_sync_block("node2")

    TestFramework.get_node_top_block("node1")

    TestFramework.get_node_top_block("node4")

    :timer.sleep(2000)

    assert :synced == TestFramework.compare_nodes_by_top_block("node1", "node4")

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  test "namings test" do
    TestFramework.sync_two_nodes("node1", "node2")

    TestFramework.sync_two_nodes("node2", "node3")

    TestFramework.sync_two_nodes("node3", "node4")

    TestFramework.mine_sync_block("node2")
    TestFramework.naming_pre_claim("node2")
    TestFramework.mine_sync_block("node2")

    # :timer.sleep 3000

    TestFramework.naming_claim("node2")
    TestFramework.mine_sync_block("node2")

    TestFramework.mine_sync_block("node4")
    TestFramework.mine_sync_block("node4")
    TestFramework.naming_update("node4")
    TestFramework.mine_sync_block("node4")

    TestFramework.mine_sync_block("node2")
    TestFramework.naming_transfer("node2")
    TestFramework.mine_sync_block("node2")

    TestFramework.mine_sync_block("node2")
    TestFramework.naming_revoke("node2")
    TestFramework.mine_sync_block("node2")

    TestFramework.get_node_top_block_hash("node1")

    TestFramework.get_node_top_block_hash("node4")

    :timer.sleep(2000)

    assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node4")
    TestFramework.delete_all_nodes()
  end

  def find_port(start_port) do
    if TestFramework.busy_port?("300#{start_port}") ||
         TestFramework.busy_port?("400#{start_port}") do
      find_port(start_port + 1)
    else
      start_port
    end
  end
end
