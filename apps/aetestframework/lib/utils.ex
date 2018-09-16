defmodule Aetestframework.Utils do
  @moduledoc """
  Helper functions and all used cmd commands 
  for sending calls to the nodes.
  """

  alias Aetestframework.Worker, as: TestFramework

  def sync_nodes(node1, node2) do
    {node2_pub, _priv} = TestFramework.get(peer_keys_cmd(), :keypair, node2)
    %{sync_port: sync_port} = Map.get(TestFramework.state(), node2)
    TestFramework.post(connect_to_peer_cmd(sync_port, node2_pub), :peer_connect, node1)
  end

  def mine_blocks(num_of_blocks_to_mine, node) do
    Enum.each(1..num_of_blocks_to_mine, fn _ ->
      TestFramework.post("Miner.mine_sync_block_to_chain()", :mine_block, node, 20_000)
    end)
  end

  def connect_to_peer_cmd(sync_port, pubkey) do
    "Peers.try_connect(%{host: 'localhost', port: #{sync_port}, pubkey: #{inspect(pubkey)}})"
  end

  def all_pids_cmd do
    "Peers.all_pids()
    |> :erlang.term_to_binary()
    |> Base.encode32()"
  end

  def top_block_cmd do
    "Chain.top_block() 
    |> :erlang.term_to_binary() 
    |> Base.encode32()"
  end

  def top_header_hash_cmd do
    "Chain.top_block().header 
    |> BlockValidation.block_header_hash()
    |> :erlang.term_to_binary() 
    |> Base.encode32()"
  end

  def pool_cmd do
    "Pool.get_pool() 
    |> :erlang.term_to_binary() 
    |> Base.encode32()"
  end

  def simulate_spend_tx_cmd do
    "Keys.keypair(:sign)
    |> elem(0)
    |> Account.spend(20, 10, <<\"payload\">>)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  def send_tokens_cmd(sender_pub, sender_priv, receiver_pub, amount, fee, payload) do
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

  def balance_cmd(pubkey) do
    "Account.balance(Chain.chain_state().accounts, #{inspect(pubkey)})
    |> :erlang.term_to_binary() 
    |> Base.encode32()"
  end

  def sign_keys_cmd do
    "Keys.keypair(:sign)
    |> :erlang.term_to_binary()
    |> Base.encode32()"
  end

  def peer_keys_cmd do
    "Keys.keypair(:peer)
    |> :erlang.term_to_binary()
    |> Base.encode32()"
  end

  def oracle_register_cmd do
    "Oracle.register(\"{foo: bar}\",\"boolean()\", 5, 5, %{ttl: 100, type: :relative}, 1234)"
  end

  def oracle_query_cmd(query_ttl, response_ttl) do
    "Keys.keypair(:sign)
    |> elem(0)
    |> Oracle.query(\"How are you?\", 5, 5, #{query_ttl}, #{response_ttl}, 1234)"
  end

  def oracle_respond_cmd(sender, nonce, oracle_address) do
    "OracleQueryTx.id(#{inspect(sender)}, #{nonce}, #{inspect(oracle_address)})
      |> Oracle.respond(\"I am fine, thanks!\", 5, 1234)"
  end

  def oracle_extend_cmd do
    "Oracle.extend(%{ttl: 3, type: :relative}, 10)"
  end

  def name_preclaim_cmd do
    "Account.pre_claim(\"test.aet\", 123, 10)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  def name_claim_cmd do
    "Account.claim(\"test.aet\", 123, 10)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  def name_update_cmd do
    "Account.name_update(\"test.aet\", \"{\\\"test\\\":2}\", 10, 5000, 50)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  def name_transfer_cmd(transfer_to) do
    "Account.name_transfer(\"test.aet\", 
    #{inspect(transfer_to)}, 10)
    |> elem(1)
    |> Pool.add_transaction()"
  end

  def name_revoke_cmd(pubkey, privkey) do
    "Account.name_revoke(
    #{inspect(pubkey)}, 
    #{inspect(privkey, limit: :infinity)},
    \"test.aet\", 
    10,
    Account.nonce(Chain.chain_state().accounts, #{inspect(pubkey)}) + 1)
    |> elem(1)
    |> Pool.add_transaction()"
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
