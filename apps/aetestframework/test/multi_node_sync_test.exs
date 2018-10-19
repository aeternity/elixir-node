defmodule MultiNodeSyncTest do
  use ExUnit.Case

  alias Aetestframework.Worker, as: TestFramework

  alias Aetestframework.Utils
  alias Aetestframework.Worker.Supervisor, as: FrameworkSup
  alias Aecore.Naming.Tx.{NamePreClaimTx, NameClaimTx, NameUpdateTx, NameTransferTx, NameRevokeTx}
  alias Aecore.Oracle.Tx.{OracleExtendTx, OracleRegistrationTx, OracleResponseTx, OracleQueryTx}
  alias Aecore.Account.Tx.SpendTx

  setup_all do
    FrameworkSup.start_link()
    :ok
  end

  setup do
    :ok = TestFramework.new_nodes([{:node1, 5}, {:node2, 6}, {:node3, 7}, {:node4, 8}])

    Utils.sync_nodes(:node1, :node2)
    Utils.sync_nodes(:node2, :node3)
    Utils.sync_nodes(:node3, :node4)

    # Check that all nodes have enough number of peers
    assert TestFramework.verify_with_delay(
             fn ->
               [
                 Utils.all_peers_cmd()
                 |> TestFramework.get(:peers_cmd, :node1)
                 |> length(),
                 Utils.all_peers_cmd()
                 |> TestFramework.get(:peers_cmd, :node3)
                 |> length()
               ] ==
                 [
                   Utils.all_peers_cmd()
                   |> TestFramework.get(:peers_cmd, :node2)
                   |> length(),
                   Utils.all_peers_cmd()
                   |> TestFramework.get(:peers_cmd, :node4)
                   |> length()
                 ]
             end,
             5
           ) == true

    on_exit(fn ->
      TestFramework.delete_all_nodes()
      :ok
    end)
  end

  @tag :sync_test_spend
  test "spend_tx test" do
    Utils.mine_blocks(1, :node1)

    # Create a Spend transaction and add it to the pool
    TestFramework.post(Utils.simulate_spend_tx_cmd(), :spend_tx_cmd, :node1)

    # Check that Spend transaction is added to the pool
    assert transaction_added_to_pool(SpendTx)

    Utils.mine_blocks(1, :node1)

    # Check if the top Header hash is equal among the nodes
    assert same_top_header_hash() == true
  end

  @tag :sync_test_oracles
  @tag timeout: 100_000
  test "oracles test" do
    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true

    # Create an Oracle Register transaction and add it to the pool
    TestFramework.post(Utils.oracle_register_cmd(), :oracle_register_cmd, :node2)

    # Check that OracleRegister transaction is added to the pool
    assert transaction_added_to_pool(OracleRegistrationTx) == true

    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true

    # Create an Oracle Query transaction and add it to the pool
    query_ttl = "%{ttl: 10, type: :relative}"
    response_ttl = "%{ttl: 20, type: :relative}"
    TestFramework.post(Utils.oracle_query_cmd(query_ttl, response_ttl), :oracle_query_cmd, :node2)

    # Check that OracleQuery transaction is added to the pool
    assert transaction_added_to_pool(OracleQueryTx) == true

    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true

    %Aecore.Chain.Block{txs: txs} =
      TestFramework.get(Utils.top_block_cmd(), :top_block_cmd, :node2)

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
    TestFramework.post(
      Utils.oracle_respond_cmd(sender, nonce, oracle_address),
      :oracle_respond_cmd,
      :node2
    )

    # Check that OracleResponse transaction is added to the pool
    assert transaction_added_to_pool(OracleResponseTx) == true

    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true

    # Create OracleExtend transaction and add it to the pool
    TestFramework.post(Utils.oracle_extend_cmd(), :oracle_extend_cmd, :node2)

    # Check that OracleExtend transaction is added to the pool
    assert transaction_added_to_pool(OracleExtendTx) == true

    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true
  end

  @tag :sync_test_naming
  @tag timeout: 100_000
  test "namings test" do
    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true

    # Create a Naming PreClaim transaction and add it to the pool
    TestFramework.post(Utils.name_preclaim_cmd(), :name_preclaim_cmd, :node2)

    # Check that NamePreClaim transaction is added to the pool
    assert transaction_added_to_pool(NamePreClaimTx) == true

    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true

    # Check that NameClaim transaction is added to the pool
    TestFramework.post(Utils.name_claim_cmd(), :name_claim_cmd, :node2)

    assert transaction_added_to_pool(NameClaimTx) == true

    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true

    # Create a Naming Update transaction and add it to the pool
    TestFramework.post(Utils.name_update_cmd(), :name_update_cmd, :node2)

    # Check that NameUpdate transaction is added to the pool
    assert transaction_added_to_pool(NameUpdateTx) == true

    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true

    {node2_pub, node2_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair_cmd, :node2)

    # Create a Name Transfer transaction and add it to the pool
    TestFramework.post(Utils.name_transfer_cmd(node2_pub), :name_transfer, :node2)

    # Check that NameTransfer transaction is added to the pool
    assert transaction_added_to_pool(NameTransferTx) == true

    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true

    # Create a Naming Revoke transaction and add it to the pool
    TestFramework.post(Utils.name_revoke_cmd(node2_pub, node2_priv), :name_revoke_cmd, :node2)

    # Check that NameRevoke transaction is added to the pool
    assert transaction_added_to_pool(NameRevokeTx) == true

    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true
  end

  @tag :sync_test_accounts
  test "balance test" do
    # Get signing keys of all nodes
    {node1_pub, node1_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair_cmd, :node1)
    {node2_pub, node2_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair_cmd, :node2)
    {node3_pub, node3_priv} = TestFramework.get(Utils.sign_keys_cmd(), :keypair_cmd, :node3)
    {node4_pub, _} = TestFramework.get(Utils.sign_keys_cmd(), :keypair_cmd, :node4)

    # Mine 2 blocks, so that node1 has enough tokens to spend
    Utils.mine_blocks(2, :node1)
    assert same_top_header_hash() == true

    assert TestFramework.verify_with_delay(
             fn ->
               TestFramework.get(Utils.balance_cmd(node1_pub), :balance_cmd, :node1) ==
                 20_000_000_000_000_000_000
             end,
             5
           ) == true

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
      :send_tokens_cmd,
      :node1
    )

    # Check that Spend transaction is added to the pool
    assert transaction_added_to_pool(SpendTx) == true

    Utils.mine_blocks(1, :node1)
    assert same_top_header_hash() == true

    assert TestFramework.verify_with_delay(
             fn ->
               TestFramework.get(Utils.balance_cmd(node3_pub), :balance_cmd, :node3) == 50
             end,
             10
           ) == true

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
      :send_tokens_cmd,
      :node3
    )

    # Check that Spend transaction is added to the pool
    assert transaction_added_to_pool(SpendTx) == true

    Utils.mine_blocks(1, :node3)
    assert same_top_header_hash() == true

    assert TestFramework.verify_with_delay(
             fn ->
               TestFramework.get(Utils.balance_cmd(node2_pub), :balance_cmd, :node2) == 20
             end,
             5
           ) == true

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
      :send_tokens_cmd,
      :node2
    )

    # Check that Spend transaction is added to the pool
    assert transaction_added_to_pool(SpendTx) == true

    Utils.mine_blocks(1, :node2)
    assert same_top_header_hash() == true

    # Check that all nodes have correct amount
    assert TestFramework.verify_with_delay(
             fn ->
               TestFramework.get(Utils.balance_cmd(node1_pub), :balance_cmd, :node4) ==
                 29_999_999_999_999_999_950 &&
                 TestFramework.get(Utils.balance_cmd(node2_pub), :balance_cmd, :node4) ==
                   10_000_000_000_000_000_010 &&
                 TestFramework.get(Utils.balance_cmd(node3_pub), :balance_cmd, :node4) ==
                   10_000_000_000_000_000_030 &&
                 TestFramework.get(Utils.balance_cmd(node4_pub), :balance_cmd, :node4) == 10
             end,
             5
           ) == true
  end

  defp same_top_header_hash do
    TestFramework.verify_with_delay(
      fn ->
        hash1 = TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node1)

        hash1 == TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node2) &&
          hash1 == TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node3) &&
          hash1 == TestFramework.get(Utils.top_header_hash_cmd(), :top_header_hash_cmd, :node4)
      end,
      5
    )
  end

  defp transaction_added_to_pool(tx_type) do
    TestFramework.verify_with_delay(
      fn ->
        Utils.has_type_in_pool?(:node2, tx_type)
      end,
      5
    )
  end
end
