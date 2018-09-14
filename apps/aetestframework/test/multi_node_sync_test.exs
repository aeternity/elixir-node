defmodule MultiNodeSyncTest do
  use ExUnit.Case

  alias Aetestframework.Worker, as: TestFramework
  alias Aetestframework.Utils
  alias Aetestframework.Worker.Supervisor, as: FrameworkSup

  setup do
    FrameworkSup.start_link()

    port1 = Utils.find_port(1)
    TestFramework.new_node(:node1, port1)

    port2 = Utils.find_port(port1 + 1)
    TestFramework.new_node(:node2, port2)

    port3 = Utils.find_port(port2 + 1)
    TestFramework.new_node(:node3, port3)

    port4 = Utils.find_port(port3 + 1)
    TestFramework.new_node(:node4, port4)

    Utils.sync_nodes(:node1, :node2)
    Utils.sync_nodes(:node2, :node3)
    Utils.sync_nodes(:node3, :node4)

    assert length(
             TestFramework.call_with_delay(
               Utils.all_pids_cmd(),
               &TestFramework.get/4,
               :peer_pids,
               :node1,
               5000
             )
           ) == 3

    on_exit(fn ->
      :ok
    end)
  end

  @tag :sync_test
  test "spend_tx test" do
    Utils.mine_blocks(1, :node1)

    # Create a Spend transaction and add it to the pool
    TestFramework.post(Utils.simulate_spend_tx_cmd(), :spend_tx, :node1)

    # Check that we have only 1 transaction added to the pool
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node1)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node1)

    # Check if the top Header hash is equal between node2 and node4
    # Delay for 2 seconds to be sure the blocks from node2 are
    # gossiped to node4
    assert TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash, :node1) ==
             TestFramework.call_with_delay(
               Utils.top_header_hash_cmd(),
               &TestFramework.get/4,
               :top_header_hash,
               :node4,
               10_000
             )

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  @tag timeout: 100_000
  test "oracles test" do
    Utils.mine_blocks(1, :node2)

    # Create an Oracle Register transaction and add it to the pool
    TestFramework.post(Utils.oracle_register_cmd(), :oracle_register, :node2)

    # Check that the pool has only 1 transaction
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node2)

    # Create an Oracle Query transaction and add it to the pool
    query_ttl = "%{ttl: 10, type: :relative}"
    response_ttl = "%{ttl: 20, type: :relative}"
    TestFramework.post(Utils.oracle_query_cmd(query_ttl, response_ttl), :oracle_query, :node2)

    # Check that the pool has only 1 transaction
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node2)

    %Aecore.Chain.Block{txs: txs} = TestFramework.get(Utils.top_block_cmd(), :top_block, :node2)

    # Get the required data for creating the correct OracleQueryTxId
    [%Aecore.Tx.SignedTx{data: data}] = txs

    %Aecore.Tx.DataTx{
      nonce: nonce,
      payload: %Aecore.Oracle.Tx.OracleQueryTx{
        oracle_address: %Aecore.Chain.Identifier{value: oracle_address}
      },
      senders: [
        %Aecore.Chain.Identifier{value: sender}
      ]
    } = data

    # Make a OracleRespond transaction and add it to the pool
    TestFramework.post(Utils.oracle_respond_cmd(sender, nonce, oracle_address), :oracle_respond, :node2)

    # Check that the pool has only 1 transaction
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node2)

    # Create OracleExtend transaction and add it to the pool
    TestFramework.post(Utils.oracle_extend_cmd(), :oracle_extend, :node2)

    # Check if the pool is filed with one trasaction
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node2)

    # Check if the top Header hash is equal between node2 and node4
    # Delay for 2 seconds to be sure the blocks from node2 are
    # gossiped to node4
    assert TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash, :node2) ==
             TestFramework.call_with_delay(
               Utils.top_header_hash_cmd(),
               &TestFramework.get/4,
               :top_header_hash,
               :node4,
               10_000
             )

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  @tag timeout: 100_000
  test "namings test" do
    Utils.mine_blocks(1, :node2)

    # Create a Naming PreClaim transaction and add it to the pool
    TestFramework.post(Utils.name_preclaim_cmd(), :name_preclaim_tx, :node2)

    # Check if the pool is filed with one trasactiona
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node2)

    # Create a Naming Claim transaction and add it to the pool
    TestFramework.post(Utils.name_claim_cmd(), :name_claim_tx, :node2)

    # Check if the pool is filed with one trasactiona
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node2)

    # Create a Naming Update transaction and add it to the pool
    TestFramework.post(Utils.name_update_cmd(), :name_update, :node2)

    # Check if the pool is filed with one trasactiona
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node2)

    # Create a Name Transfer transaction and add it to the pool
    TestFramework.post(Utils.name_transfer_cmd(), :name_transfer, :node2)

    # Check if the pool is filed with one trasactiona
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node2)

    # Create a Naming Revoke transaction and add it to the pool
    TestFramework.post(Utils.name_revoke_cmd(), :name_revoke, :node2)

    # Check if the pool is filed with one trasactiona
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node2)

    # Check if the top Header hash is equal between node2 and node4
    # Delay for 2 seconds to be sure the blocks from node2 are
    # gossiped to node4
    assert TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash, :node2) ==
             TestFramework.call_with_delay(
               Utils.top_header_hash_cmd(),
               &TestFramework.get/4,
               :top_header_hash,
               :node3,
               10_000
             )

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  test "balance test" do
    # Mine 2 blocks, so that node1 has enough tokens to spend
    Utils.mine_blocks(2, :node1)

    {node1_pub, node1_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair, :node1)
    {node2_pub, node2_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair, :node2)
    {node3_pub, node3_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair, :node3)
    {node4_pub, _} = TestFramework.get(Utils.sign_keys_cmd(), :keypair, :node4)

    amount1 = 50
    fee = 10
    payload = <<"test">>

    # Create SpendTx transaction
    # Send 50 tokens from node1 to node3
    # Add the transaction to the pool
    TestFramework.post(
      Utils.send_tokens_cmd(
        node1_pub,
        node1_priv,
        node3_pub,
        amount1,
        fee,
        payload
      ),
      :send_tokens,
      :node1
    )

    # Check that the transaction is added to the pool
    assert Utils.pool_cmd()
           |> TestFramework.get(:txs_pool, :node1)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node1)

    # Create SpendTx transaction
    # Send 20 tokens from node3 to node2
    # Add the transaction to the pool
    amount2 = 20

    TestFramework.post(
      Utils.send_tokens_cmd(
        node3_pub,
        node3_priv,
        node2_pub,
        amount2,
        fee,
        payload
      ),
      :send_tokens,
      :node3
    )

    # Check that the transaction is added to the pool
    assert Utils.pool_cmd()
           |> TestFramework.call_with_delay(&TestFramework.get/4, :txs_pool, :node3, 3000)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node3)

    # Create SpendTx transaction
    # Send 10 tokens from node2 to node4
    # Add the transaction to the pool
    amount3 = 10

    TestFramework.post(
      Utils.send_tokens_cmd(
        node2_pub,
        node2_priv,
        node4_pub,
        amount3,
        fee,
        payload
      ),
      :send_tokens,
      :node2
    )

    # Check that the transaction is added to the pool
    assert Utils.pool_cmd()
           |> TestFramework.call_with_delay(&TestFramework.get/4, :txs_pool, :node2, 3000)
           |> Map.to_list()
           |> length() == 1

    Utils.mine_blocks(1, :node2)

    # Check that node4 has 10 tokens
    assert node4_pub
           |> Utils.balance_cmd()
           |> TestFramework.call_with_delay(&TestFramework.get/4, :balance, :node4, 3000) == 10

    TestFramework.delete_all_nodes()
  end
end
