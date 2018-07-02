defmodule MultiNodeSyncTest do
  use ExUnit.Case
  alias Aecore.MultiNodeTestFramework.Worker, as: TestFramework

  setup do
    TestFramework.start_link(%{})

    on_exit(fn ->
      :ok
    end)
  end

  @tag timeout: 120_000
  @tag :sync_test
  test "test nodes sync", setup do
    port1 = find_port(4001)
    TestFramework.new_node("node1", port1)

    :timer.sleep(4000)

    port2 = find_port(port1)
    TestFramework.new_node("node2", port2)

    :timer.sleep(4000)

    port3 = find_port(port2)
    TestFramework.new_node("node3", port3)

    :timer.sleep(4000)

    port4 = find_port(port3)
    TestFramework.new_node("node4", port4)
    :timer.sleep(4000)
    TestFramework.sync_two_nodes("node1", "node2")
    TestFramework.sync_two_nodes("node4", "node1")
    TestFramework.sync_two_nodes("node2", "node3")

    TestFramework.mine_sync_block("node1")
    TestFramework.spend_tx("node1")
    TestFramework.mine_sync_block("node1")

    TestFramework.register_oracle("node2")
    TestFramework.mine_sync_block("node2")

    TestFramework.extend_oracle("node2")
    TestFramework.mine_sync_block("node2")

    TestFramework.spend_tx("node3")
    TestFramework.mine_sync_block("node3")

    TestFramework.naming_pre_claim("node3")
    TestFramework.mine_sync_block("node3")

    TestFramework.spend_tx("node4")
    TestFramework.mine_sync_block("node4")

    :timer.sleep(3000)
    assert :synced == TestFramework.compare_nodes_by_top_block("node1", "node2")
    assert :synced == TestFramework.compare_nodes_by_registered_oracles("node1", "node2")
    assert :synced == TestFramework.compare_nodes_by_top_block("node2", "node3")

    assert :synced == TestFramework.compare_nodes_by_top_block("node3", "node4")
    assert :synced == TestFramework.compare_nodes_by_registered_oracles("node3", "node4")

    assert :synced == TestFramework.compare_nodes_by_top_block("node4", "node1")
    assert :synced == TestFramework.compare_nodes_by_registered_oracles("node4", "node1")
    TestFramework.delete_all_nodes()
  end

  def find_port(start_port) do
    if TestFramework.busy_port?(start_port) do
      find_port(start_port + 1)
    else
      start_port
    end
  end
end
