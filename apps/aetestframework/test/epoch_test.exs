defmodule EpochTest do
  use ExUnit.Case

  alias Aetestframework.Worker, as: TestFramework
  alias Aetestframework.Epoch

  setup do
    TestFramework.Supervisor.start_link(%{})

    port1 = find_port(1)
    TestFramework.new_node("node1", port1)

    port2 = find_port(port1 + 1)
    TestFramework.new_node("node2", port2)

    Epoch.start_epoch(System.get_env("EPOCH_PATH"))

    TestFramework.sync_two_nodes("node1", "node2")
    TestFramework.get_all_peers("node2")

    Epoch.sync_with_elixir("node1")
    TestFramework.get_all_peers("node1")

    on_exit(fn ->
      :ok
    end)
  end

  @tag :epoch_sync_test
  @tag timeout: 240_000
  test "spend_tx test" do
    TestFramework.mine_sync_block("node1")
    TestFramework.spend_tx("node1")
    TestFramework.mine_sync_block("node1")

    assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node2")
    assert :synced == Epoch.compare_hash "node1"
    assert :synced == Epoch.compare_hash "node2"

    Epoch.stop_epoch()
    TestFramework.delete_all_nodes()
  end

  @tag :epoch_sync_test
  @tag timeout: 240_000
  test "oracles test" do
    TestFramework.mine_sync_block("node2")
    TestFramework.register_oracle("node2")
    TestFramework.mine_sync_block("node2")

    # TestFramework.query_oracle("node2")
    # TestFramework.mine_sync_block("node2")

    # TestFramework.extend_oracle("node2")
    # TestFramework.mine_sync_block("node2")

    # TestFramework.respond_oracle("node2")
    # TestFramework.mine_sync_block("node2")

    assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node2")
    assert :synced == Epoch.compare_hash "node1"
    assert :synced == Epoch.compare_hash "node2"

    Epoch.stop_epoch()
    TestFramework.delete_all_nodes()
  end

  @tag :epoch_sync_test
  @tag timeout: 240_000
  test "naming test" do
    TestFramework.mine_sync_block("node2")
    TestFramework.naming_pre_claim("node2")
    TestFramework.mine_sync_block("node2")

    TestFramework.naming_claim("node2")
    TestFramework.mine_sync_block("node2")

    # TestFramework.mine_sync_block("node2")
    # TestFramework.naming_update("node2")
    # TestFramework.mine_sync_block("node2")

    TestFramework.mine_sync_block("node2")
    TestFramework.naming_transfer("node2")
    TestFramework.mine_sync_block("node2")

    TestFramework.mine_sync_block("node2")
    TestFramework.naming_revoke("node2")
    TestFramework.mine_sync_block("node2")

    assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node2")
    assert :synced == Epoch.compare_hash "node1"
    assert :synced == Epoch.compare_hash "node2"

    Epoch.stop_epoch()
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
