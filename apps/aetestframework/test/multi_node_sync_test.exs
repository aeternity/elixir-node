defmodule MultiNodeSyncTest do
  use ExUnit.Case

  alias Aetestframework.Worker, as: TestFramework

  setup do
    TestFramework.start_link()

    port1 = find_port(1)
    TestFramework.new_node(:node1, port1)

    port2 = find_port(port1 + 1)
    TestFramework.new_node(:node2, port2)

    port3 = find_port(port2 + 1)
    TestFramework.new_node(:node3, port3)

    port4 = find_port(port3 + 1)
    TestFramework.new_node(:node4, port4)

    sync_nodes(:node1, :node2)
    sync_nodes(:node2, :node3)
    sync_nodes(:node3, :node4)

    assert length(
             TestFramework.call_with_delay(
               get_all_pids_cmd(),
               &TestFramework.get/4,
               :peer_pids,
               :node1,
               3000
             )
           ) == 3

    on_exit(fn ->
      :ok
    end)
  end

  @tag :sync_test
  test "spend_tx test" do
    mine_blocks(1, :node1)

    # Create a Spend transaction and add it to the pool
    TestFramework.post(simulate_spend_tx_cmd(), :spend_tx, :node1)

    # Check that we have only 1 transaction added to the pool
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node1)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node1)

    # Check if the top Header hash is equal between node2 and node4
    # Delay for 2 seconds to be sure the blocks from node2 are
    # gossiped to node4
    assert TestFramework.get(top_header_hash_cmd(), :top_header_hash, :node1) ==
             TestFramework.call_with_delay(
               top_header_hash_cmd(),
               &TestFramework.get/4,
               :top_header_hash,
               :node4,
               5000
             )

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  @tag timeout: 100_000
  test "oracles test" do
    mine_blocks(1, :node2)

    # Create an Oracle Register transaction and add it to the pool
    TestFramework.post(oracle_register_cmd(), :oracle_register, :node2)

    # Check that the pool has only 1 transaction
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node2)

    # Create an Oracle Query transaction and add it to the pool
    query_ttl = "%{ttl: 10, type: :relative}"
    response_ttl = "%{ttl: 20, type: :relative}"
    TestFramework.post(oracle_query_cmd(query_ttl, response_ttl), :oracle_query, :node2)

    # Check that the pool has only 1 transaction
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node2)

    %Aecore.Chain.Block{txs: txs} = TestFramework.get(get_top_block_cmd(), :top_block, :node2)

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
    TestFramework.post(oracle_respond_cmd(sender, nonce, oracle_address), :oracle_respond, :node2)

    # Check that the pool has only 1 transaction
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node2)

    # Create OracleExtend transaction and add it to the pool
    TestFramework.post(oracle_extend_cmd(), :oracle_extend, :node2)

    # Check if the pool is filed with one trasaction
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node2)

    # Check if the top Header hash is equal between node2 and node4
    # Delay for 2 seconds to be sure the blocks from node2 are
    # gossiped to node4
    assert TestFramework.get(top_header_hash_cmd(), :top_header_hash, :node2) ==
             TestFramework.call_with_delay(
               top_header_hash_cmd(),
               &TestFramework.get/4,
               :top_header_hash,
               :node4,
               5000
             )

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  @tag timeout: 100_000
  test "namings test" do
    mine_blocks(1, :node2)

    # Create a Naming PreClaim transaction and add it to the pool
    TestFramework.post(name_preclaim_cmd(), :name_preclaim_tx, :node2)

    # Check if the pool is filed with one trasactiona
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node2)

    # Create a Naming Claim transaction and add it to the pool
    TestFramework.post(name_claim_cmd(), :name_claim_tx, :node2)

    # Check if the pool is filed with one trasactiona
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node2)

    # Create a Naming Update transaction and add it to the pool
    TestFramework.post(name_update_cmd(), :name_update, :node2)

    # Check if the pool is filed with one trasactiona
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node2)

    # Create a Name Transfer transaction and add it to the pool
    TestFramework.post(name_transfer_cmd(), :name_transfer, :node2)

    # Check if the pool is filed with one trasactiona
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node2)

    # Create a Naming Revoke transaction and add it to the pool
    TestFramework.post(name_revoke_cmd(), :name_revoke, :node2)

    # Check if the pool is filed with one trasactiona
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node2)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node2)

    # Check if the top Header hash is equal between node2 and node4
    # Delay for 2 seconds to be sure the blocks from node2 are
    # gossiped to node4
    assert TestFramework.get(top_header_hash_cmd(), :top_header_hash, :node2) ==
             TestFramework.call_with_delay(
               top_header_hash_cmd(),
               &TestFramework.get/4,
               :top_header_hash,
               :node3,
               5000
             )

    TestFramework.delete_all_nodes()
  end

  @tag :sync_test
  test "balance test" do
    # Mine 2 blocks, so that node1 has enough tokens to spend
    mine_blocks(2, :node1)

    {node1_pub, node1_priv} = TestFramework.get(sign_keys_cmd(), :keypair, :node1)
    {node2_pub, node2_priv} = TestFramework.get(sign_keys_cmd(), :keypair, :node2)
    {node3_pub, node3_priv} = TestFramework.get(sign_keys_cmd(), :keypair, :node3)
    {node4_pub, _} = TestFramework.get(sign_keys_cmd(), :keypair, :node4)

    amount1 = 50
    fee = 10
    payload = <<"test">>

    # Create SpendTx transaction
    # Send 50 tokens from node1 to node3
    # Add the transaction to the pool
    TestFramework.post(
      send_tokens_cmd(
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
    assert get_pool_cmd()
           |> TestFramework.get(:txs_pool, :node1)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node1)

    # Create SpendTx transaction
    # Send 20 tokens from node3 to node2
    # Add the transaction to the pool
    amount2 = 20

    TestFramework.post(
      send_tokens_cmd(
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
    assert get_pool_cmd()
           |> TestFramework.call_with_delay(&TestFramework.get/4, :txs_pool, :node3, 1000)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node3)

    # Create SpendTx transaction
    # Send 10 tokens from node2 to node4
    # Add the transaction to the pool
    amount3 = 10

    TestFramework.post(
      send_tokens_cmd(
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
    assert get_pool_cmd()
           |> TestFramework.call_with_delay(&TestFramework.get/4, :txs_pool, :node2, 1000)
           |> Map.to_list()
           |> length() == 1

    mine_blocks(1, :node2)

    # Check that node4 has 10 tokens
    assert node4_pub
           |> get_balance_cmd()
           |> TestFramework.call_with_delay(&TestFramework.get/4, :balance, :node4, 1000) == 10

    TestFramework.delete_all_nodes()
  end

  ## Helper functions
  defp sync_nodes(node1, node2) do
    {node2_pub, _priv} = TestFramework.get(peer_keys_cmd(), :keypair, node2)
    %{sync_port: sync_port} = Map.get(TestFramework.state(), node2)
    TestFramework.post(connect_to_peer_cmd(sync_port, node2_pub), :peer_connect, node1)
  end

  defp mine_blocks(num_of_blocks_to_mine, node) do
    Enum.each(1..num_of_blocks_to_mine, fn _ ->
      TestFramework.post("Miner.mine_sync_block_to_chain()", :mine_block, node, 20_000)
    end)
  end

  defp connect_to_peer_cmd(sync_port, pubkey) do
    "Peers.try_connect(%{host: 'localhost', port: #{sync_port}, pubkey: #{inspect(pubkey)}})"
  end

  defp get_all_pids_cmd do
    "Peers.all_pids()
    |> :erlang.term_to_binary()
    |> Base.encode32()"
  end

  defp get_top_block_cmd do
    "Chain.top_block() 
    |> :erlang.term_to_binary() 
    |> Base.encode32()"
  end

  defp top_header_hash_cmd do
    "Chain.top_block().header 
    |> BlockValidation.block_header_hash()
    |> :erlang.term_to_binary() 
    |> Base.encode32()"
  end

  defp get_pool_cmd do
    "Pool.get_pool() 
    |> :erlang.term_to_binary() 
    |> Base.encode32()"
  end

  defp simulate_spend_tx_cmd do
    "Keys.keypair(:sign)
    |> elem(0)
    |> Account.spend(20, 10, <<\"payload\">>)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  defp send_tokens_cmd(sender_pub, sender_priv, receiver_pub, amount, fee, payload) do
    "Account.spend(
    #{inspect(sender_pub)}, 
    #{inspect(sender_priv, limit: :infinity)}, 
    #{inspect(receiver_pub)}, 
    #{amount}, 
    #{fee}, 
    Account.nonce(Chain.chain_state().accounts, #{inspect(sender_pub)}) + 1, 
    \"#{payload}\")
    |> elem(1)
    |> Pool.add_transaction()"
  end

  defp get_balance_cmd(pubkey) do
    "Account.balance(Chain.chain_state().accounts, #{inspect(pubkey)})
    |> :erlang.term_to_binary() 
    |> Base.encode32()"
  end

  defp sign_keys_cmd do
    "Keys.keypair(:sign)
    |> :erlang.term_to_binary()
    |> Base.encode32()"
  end

  defp peer_keys_cmd do
    "Keys.keypair(:peer)
    |> :erlang.term_to_binary()
    |> Base.encode32()"
  end

  defp oracle_register_cmd do
    "Oracle.register(\"{foo: bar}\",\"boolean()\", 5, 5, %{ttl: 100, type: :relative}, 1234)"
  end

  defp oracle_query_cmd(query_ttl, response_ttl) do
    "Keys.keypair(:sign)
    |> elem(0)
    |> Oracle.query(\"How are you?\", 5, 5, #{query_ttl}, #{response_ttl}, 1234)"
  end

  defp oracle_respond_cmd(sender, nonce, oracle_address) do
    "OracleQueryTx.id(#{inspect(sender)}, #{nonce}, #{inspect(oracle_address)})
      |> Oracle.respond(\"I am fine, thanks!\", 5, 1234)"
  end

  defp oracle_extend_cmd do
    "Oracle.extend(%{ttl: 3, type: :relative}, 10)"
  end

  defp name_preclaim_cmd do
    "Account.pre_claim(\"test.aet\", 123, 10)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  defp name_claim_cmd do
    "Account.claim(\"test.aet\", 123, 10)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  defp name_update_cmd do
    "Account.name_update(\"test.aet\", \"{\\\"test\\\":2}\", 10, 5000, 50)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  defp name_transfer_cmd do
    "Account.name_transfer(\"test.aet\", 
    Keys.keypair(:sign) |> elem(0), 10)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  defp name_revoke_cmd do
    "Keys.keypair(:sign)
    |> elem(0)
    |> Account.name_revoke(Keys.keypair(:sign) |> elem(1), 
    \"test.aet\", 10,
    Account.nonce(Chain.chain_state().accounts, 
    Keys.keypair(:sign) |> elem(0)) + 1)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  defp find_port(start_port) do
    if TestFramework.busy_port?("300#{start_port}") ||
         TestFramework.busy_port?("400#{start_port}") do
      find_port(start_port + 1)
    else
      start_port
    end
  end
end
