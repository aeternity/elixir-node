defmodule MultiNodeSyncTest do
  use ExUnit.Case

  alias Aetestframework.Worker, as: TestFramework
  alias Aecore.Naming.Tx.{NamePreClaimTx, NameClaimTx, NameUpdateTx, NameTransferTx, NameRevokeTx}
  alias Aecore.Oracle.Tx.{OracleExtendTx, OracleRegistrationTx, OracleResponseTx, OracleQueryTx}
  alias Aecore.Account.Tx.SpendTx

  setup do
    TestFramework.start_link(%{})

    port1 = find_port(1)
    TestFramework.new_node("node1", port1)

    port2 = find_port(port1 + 1)
    TestFramework.new_node("node2", port2)

    port3 = find_port(port2 + 1)
    TestFramework.new_node("node3", port3)

    port4 = find_port(port3 + 1)
    TestFramework.new_node("node4", port4)

    TestFramework.sync_two_nodes("node1", "node2")
    TestFramework.get_all_peers "node2"

    TestFramework.sync_two_nodes("node2", "node3")
    TestFramework.get_all_peers "node3"

    TestFramework.sync_two_nodes("node3", "node4")
    TestFramework.get_all_peers "node4"

    on_exit(fn ->
      :ok
    end)
  end

  @tag :sync_test
  test "spend_tx test" do
    TestFramework.mine_sync_block("node1")
    TestFramework.spend_tx("node1")
    assert TestFramework.get_pool_tx_count("node1") == 1
    TestFramework.mine_sync_block("node1")
    assert TestFramework.get_latest_tx_type("node1") == SpendTx

    assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node4")

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  @tag timeout: 100_000
  test "oracles test" do
    TestFramework.mine_sync_block("node2")
    TestFramework.register_oracle("node2")
    assert TestFramework.get_pool_tx_count("node2") == 1
    TestFramework.mine_sync_block("node2")
    assert TestFramework.get_latest_tx_type("node3") == OracleRegistrationTx

    TestFramework.query_oracle("node2")
    assert TestFramework.get_pool_tx_count("node2") == 1
    TestFramework.mine_sync_block("node2")
    assert TestFramework.get_latest_tx_type("node4") == OracleQueryTx

    TestFramework.extend_oracle("node2")
    assert TestFramework.get_pool_tx_count("node2") == 1
    TestFramework.mine_sync_block("node2")
    assert TestFramework.get_latest_tx_type("node1") == OracleExtendTx

    TestFramework.respond_oracle("node2")
    assert TestFramework.get_pool_tx_count("node2") == 1
    TestFramework.mine_sync_block("node2")
    assert TestFramework.get_latest_tx_type("node2") == OracleResponseTx

    assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node4")

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  @tag timeout: 100_000
  test "namings test" do
    TestFramework.mine_sync_block("node2")
    TestFramework.naming_pre_claim("node2")
    assert TestFramework.get_pool_tx_count("node2") == 1
    TestFramework.mine_sync_block("node2")
    assert TestFramework.get_latest_tx_type("node4") == NamePreClaimTx

    TestFramework.naming_claim("node2")
    assert TestFramework.get_pool_tx_count("node2") == 1
    TestFramework.mine_sync_block("node2")
    assert TestFramework.get_latest_tx_type("node1") == NameClaimTx

    TestFramework.mine_sync_block("node2")
    TestFramework.naming_update("node2")
    assert TestFramework.get_pool_tx_count("node2") == 1
    TestFramework.mine_sync_block("node1")
    assert TestFramework.get_latest_tx_type("node3") == NameUpdateTx

    TestFramework.mine_sync_block("node2")
    TestFramework.naming_transfer("node2")
    assert TestFramework.get_pool_tx_count("node2") == 1
    TestFramework.mine_sync_block("node2")
    assert TestFramework.get_latest_tx_type("node2") == NameTransferTx

    TestFramework.mine_sync_block("node2")
    TestFramework.naming_revoke("node2")
    assert TestFramework.get_pool_tx_count("node2") == 1
    TestFramework.mine_sync_block("node2")
    assert TestFramework.get_latest_tx_type("node4") == NameRevokeTx

    assert :synced == TestFramework.compare_nodes_by_top_block_hash("node1", "node4")

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  test "balance test" do
    TestFramework.update_pubkeys_state()

    TestFramework.mine_sync_block("node1")
    TestFramework.mine_sync_block("node1")
    TestFramework.send_tokens("node1", "node3", 50)
    assert TestFramework.get_pool_tx_count("node1") == 1
    TestFramework.mine_sync_block("node1")

    TestFramework.send_tokens("node3", "node2", 20)
    assert TestFramework.get_pool_tx_count("node3") == 1
    TestFramework.mine_sync_block("node3")
    TestFramework.send_tokens("node2", "node4", 10)
    assert TestFramework.get_pool_tx_count("node2") == 1
    TestFramework.mine_sync_block("node2")

    TestFramework.update_balance("node1")

    TestFramework.update_balance("node2")

    TestFramework.update_balance("node3")

    TestFramework.update_balance("node4")

    assert TestFramework.get_balance("node4") == 10

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
