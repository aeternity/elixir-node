defmodule Aetestframework.Worker do
  @moduledoc """
  Module for multi node sync test
  """

  alias Aehttpclient.Client
  alias Aecore.Account.Account

  require Logger
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def init(args) do
    {:ok, args}
  end

  def get_state do
    GenServer.call(__MODULE__, {:get_state})
  end

  @spec new_node(String.t(), non_neg_integer()) :: :already_exists | Map.t()
  def new_node(node_name, iex_num) do
    GenServer.call(__MODULE__, {:new_node, node_name, iex_num}, 20_000)
  end

  @spec sync_two_nodes(String.t(), String.t()) :: :ok
  def sync_two_nodes(node_name1, node_name2) do
    GenServer.call(__MODULE__, {:sync_two_nodes, node_name1, node_name2})
  end

  def update_pubkeys_state do
    GenServer.call(__MODULE__, {:update_pubkeys_state})
  end

  def get_top_block(node) do
    GenServer.call(__MODULE__, {:get_top_block, node})
  end

  def get_top_block_hash(node) do
    GenServer.call(__MODULE__, {:get_top_block_hash, node})
  end

  def get_oracle_interaction_objects(node) do
    GenServer.call(__MODULE__, {:get_oracle_interaction_objects, node})
  end

  @doc """
    Updates top block state for 2 nodes and compares them.
    If top block of each node is equal - they are synced
  """
  @spec compare_nodes_by_top_block(String.t(), String.t()) :: :synced | :not_synced
  def compare_nodes_by_top_block(node_name1, node_name2) do
    update_node_top_block(node_name1)
    update_node_top_block(node_name2)
    block1 = get_top_block(node_name1)
    block2 = get_top_block(node_name2)

    if block1 == block2 do
      :synced
    else
      :not_synced
    end
  end

  @doc """
    Updates top block hash state for 2 nodes and compares them.
    If top block hash of each node is equal - they are synced
  """
  @spec compare_nodes_by_top_block_hash(String.t(), String.t()) :: :synced | :not_synced
  def compare_nodes_by_top_block_hash(node_name1, node_name2) do
    update_node_top_block_hash(node_name1)
    update_node_top_block_hash(node_name2)
    top_block_hash1 = get_top_block_hash(node_name1)
    top_block_hash2 = get_top_block_hash(node_name2)

    if top_block_hash1 == top_block_hash2 do
      :synced
    else
      :not_synced
    end
  end

  def compare_nodes_by_oracle_interaction_objects(node_name1, node_name2) do
    update_oracle_interaction_objects(node_name1)
    update_oracle_interaction_objects(node_name2)
    oracle_int_obj1 = get_oracle_interaction_objects(node_name1)
    oracle_int_obj2 = get_oracle_interaction_objects(node_name2)

    if oracle_int_obj1 == oracle_int_obj2 do
      :synced
    else
      :not_synced
    end
  end

  @doc """
    Gets the process ports info.
  """
  def ports_info do
    GenServer.call(__MODULE__, {:ports_info})
  end

  @doc """
    Sending command in a given node.
  """
  @spec send_command(String.t(), String.t()) :: :ok | :unknown_node
  def send_command(node_name, cmd) do
    # adding \n to cmd to imitate pressing enter in iex shell
    cmd = cmd <> "\n"
    GenServer.call(__MODULE__, {:send_command, node_name, cmd}, 10_000)
  end

  @doc """
    Sending amount of tokens from one miner account to another
  """
  def send_tokens(node1, node2, amount) do
    GenServer.call(__MODULE__, {:send_tokens, node1, node2, amount})
  end

  @doc """
    Getting specified miner account balance
  """
  def get_balance(node) do
    GenServer.call(__MODULE__, {:get_balance, node})
  end

  @doc """
    Kills the process, releases the port
  """
  @spec delete_node(String.t()) :: :ok | :unknown_node
  def delete_node(node_name) do
    GenServer.call(__MODULE__, {:delete_node, node_name})
  end

  def delete_all_nodes do
    GenServer.call(__MODULE__, {:delete_all_nodes}, 20_000)
  end

  def update_balance(node_name) do
    send_command(node_name, "{pubkey, _} = Keys.keypair :sign")
    send_command(node_name, "{:acc_balance, Account.balance(Chain.chain_state().accounts, pubkey)}")
  end

  # oracles
  @spec update_oracle_interaction_objects(String.t()) :: :ok | :unknown_node
  def update_oracle_interaction_objects(node_name) do
    send_command(node_name, "oracle_tree = Chain.chain_state().oracles.oracle_tree")

    send_command(
      node_name,
      "query_id = oracle_tree |> PatriciaMerkleTree.all_keys() |> List.last()"
    )

    send_command(
      node_name,
      "interaction_object = OracleStateTree.get_query(Chain.chain_state().oracles, query_id)"
    )

    # converting the keys which are binary to string
    send_command(
      node_name,
      "encoded_int_object = :erlang.term_to_binary(interaction_object)"
    )

    send_command(
      node_name,
      "{:respond_oracle_int_obj, Base.encode32(encoded_int_object)}"
    )
  end

  @doc """
    Functions to register, extend, query, respond oracles.
    They have already defined arguments taken from the tests
  """
  @spec register_oracle(String.t()) :: :ok | :unknown_node
  def register_oracle(node_name) do
    send_command(
      node_name,
      "Oracle.register(\"{foo: bar}\",\"boolean()\", 5, 5, %{ttl: 100, type: :relative}, 1234)"
    )
  end

  @spec extend_oracle(String.t()) :: :ok | :unknown_node
  def extend_oracle(node_name) do
    send_command(node_name, "Oracle.extend(%{ttl: 3, type: :relative}, 10)")
  end

  @spec query_oracle(String.t()) :: :ok | :unknown_node
  def query_oracle(node_name) do
    send_command(node_name, "{pub_key, _} = Keys.keypair(:sign)")
    send_command(node_name, "query_ttl = %{ttl: 10, type: :relative}")
    send_command(node_name, "response_ttl = %{ttl: 20, type: :relative}")
    send_command(node_name, "Oracle.query(pub_key, \"How are you?\", 5, 5, query_ttl, response_ttl, 1234)")
  end

  @spec respond_oracle(String.t()) :: :ok | :unknown_node
  def respond_oracle(node_name) do
    send_command(node_name, "[tx]= Chain.top_block.txs")
    send_command(node_name, "data = tx.data")
    send_command(node_name, "[sender] = data.senders")
    send_command(node_name, "query_id = OracleQueryTx.id(sender.value, data.nonce, data.payload.oracle_address.value)
    ")

    send_command(
      node_name,
      "query = data.payload.oracle_address.value <> query_id"
    )

    send_command(
      node_name,
      "OracleStateTree.get_query(Chain.chain_state().oracles, query)"
    )

    send_command(
      node_name,
      "Oracle.respond(query_id, \"I am fine, thanks!\", 5, 1234)"
    )
  end

  def get_latest_tx_type(node_name) do
    send_command(node_name, "%Block{txs: txs} = Chain.top_block")
    send_command(node_name, "[tx] = txs")
    send_command(node_name, "encoded_type = :erlang.term_to_binary(tx.data.type)")
    send_command(node_name, "{:respond_tx_type, Base.encode32(encoded_type)}")
  end

  # pool

  def get_pool_tx_count(node) do
    send_command(node, "{:respond_pool_tx, Enum.count(Pool.get_pool())}")
  end

  # spend_tx

  @spec spend_tx(String.t()) :: :ok | :unknown_node
  def spend_tx(node_name) do
    send_command(node_name, "{pubkey, _} = Keys.keypair :sign")

    send_command(
      node_name,
      "Account.spend(pubkey, 20, 10, <<\"payload\">>)"
    )
  end

  # mining
  @spec mine_sync_block(String.t()) :: :ok | :unknown_node
  def mine_sync_block(node_name) do
    send_command(node_name, "Miner.mine_sync_block_to_chain()")
    update_balance(node_name)
  end

  # chain
  @spec update_node_top_block(String.t()) :: :ok | String.t()
  def update_node_top_block(node_name) do
    send_command(node_name, "top_block = Chain.top_block()")

    send_command(
      node_name,
      "encoded_block = :erlang.term_to_binary(top_block)"
    )

    send_command(
      node_name,
      "{:respond_top_block, Base.encode32(encoded_block)}"
    )
  end

  @spec update_node_top_block_hash(String.t()) :: :ok | :unknown_node
  def update_node_top_block_hash(node_name) do
    send_command(node_name, "block_hash = Chain.top_block_hash() |> :erlang.term_to_binary()")
    send_command(node_name, "{:respond_hash, Base.encode32(block_hash)}")
  end

  # naming txs

  @doc """
    Functions to pre_claim, claim, update, transfer, revoke naming txs.
    They have already defined arguments taken from the tests
  """
  @spec naming_pre_claim(String.t()) :: :ok | :unknown_node
  def naming_pre_claim(node_name) do
    send_command(
      node_name,
      "Account.pre_claim(\"test.aet\", 123, 10)"
    )

  end

  @spec naming_claim(String.t()) :: :ok | :unknown_node
  def naming_claim(node_name) do
    send_command(
      node_name,
      "Account.claim(\"test.aet\", 123, 10)"
    )

  end

  @spec naming_update(String.t()) :: :ok | :unknown_node
  def naming_update(node_name) do
    send_command(
      node_name,
      "Account.name_update(\"test.aet\", \"{\\\"test\\\":2}\", 10, 5000, 50) "
    )

  end

  @spec naming_transfer(String.t()) :: :ok | :unknown_node
  def naming_transfer(node_name) do
    send_command(node_name, "{transfer_to_pub, transfer_to_priv} = Keys.keypair(:sign)")

    send_command(
      node_name,
      "Account.name_transfer(\"test.aet\", transfer_to_pub, 10)"
    )

  end

  @spec naming_revoke(String.t()) :: :ok | :unknown_node
  def naming_revoke(node_name) do
    send_command(node_name, "{transfer_to_pub, transfer_to_priv} = Keys.keypair(:sign)")

    send_command(
      node_name,
      "Account.spend(transfer_to_pub, 15, 10, <<\"payload\">>)"
    )

    mine_sync_block(node_name)

    send_command(
      node_name,
      "next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_to_pub) + 1"
    )

    send_command(
      node_name,
      "Account.name_revoke(transfer_to_pub, transfer_to_priv, \"test.aet\", 10, next_nonce)"
    )

  end

  @spec chainstate_naming(String.t()) :: :ok | :unknown_node
  def chainstate_naming(node_name) do
    send_command(node_name, "naming_state = Chain.chain_state().naming")
    send_command(node_name, "naming_state = Chain.chain_state().naming")
  end

  @doc """
    Gets all peers for a given node
  """
  @spec get_all_peers(String.t()) :: :ok
  def get_all_peers(node_name) do
    send_command(node_name, "peers = Peers.all_peers")
    send_command(node_name, "peers_encoded = :erlang.term_to_binary(peers)")
    send_command(node_name, "{:respond_peers, Base.encode32(peers_encoded)}")
  end

  @doc """
    Checking if the port is busy
  """
  def busy_port?(port) do
    :os.cmd('lsof -i -P -n | grep -w #{port}') != []
  end

  defp update_data(state, result, respond, port, type) do
    {node, _} = Enum.find(state, fn {_, value} -> value.process_port == port end)
    data = process_result(respond, result)

    put_in(state[node][type], data)
  end

  defp process_result(respond, result) do
    one_line_res = String.replace(result, "\n", "")
    respond_res = Regex.run(~r/({#{respond}.*})/, one_line_res)
    res = Regex.run(~r/"(.*)"/, List.last(respond_res))
    base_decoded = Base.decode32!(List.last(res))
    :erlang.binary_to_term(base_decoded)
  end

  def check_peers(state, port, result) do
    one_line_res = String.replace(result, "\n", "")
    if Regex.match?(~r/({:respond_peers, \[\])/, one_line_res) do
      state
    else
      update_data(state, result, ":respond_peers", port, :peers)
    end
  end

  # server

  def handle_info(_, state) do
    {:noreply, state}
  end

  def receive_result(state) do
    receive do
      {port, {:data, result}} ->
        cond do
          result =~ ":respond_top_block" ->
            new_state = update_data(state, result, ":respond_top_block", port, :top_block)
            {:reply, :ok, new_state}

          result =~ ":respond_pool_tx" ->
            {node, _} = Enum.find(state, fn {_, value} -> value.process_port == port end)
            txs_count_str = Regex.run(~r/(\d)}/, result)
            {tx_count, _} = txs_count_str |> List.last() |> Integer.parse()
            {:reply, tx_count, state}

          result =~ ":respond_tx_type" ->
            tx_type = process_result(":respond_tx_type", result)
            {:reply, tx_type, state}

          result =~ ":respond_hash" ->
            new_state = update_data(state, result, ":respond_hash", port, :top_block_hash)
            {:reply, :ok, new_state}

          result =~ ":respond_oracle_int_obj" ->
            new_state = update_data(state, result, ":respond_oracle_int_obj", port, :oracle_interaction_objects)
            {:reply, :ok, new_state}

          result =~ ":respond_peers" ->
            new_state = check_peers(state, port, result)
            {:reply, :ok, new_state}

          result =~ ":acc_balance" ->
            {node, _} = Enum.find(state, fn {_, value} -> value.process_port == port end)
            balance_str = Regex.run(~r/\d+/, result)
            {balance, _} = balance_str |> List.first() |> Integer.parse()
            new_state = put_in(state[node].miner_balance, balance)
            {:reply, :ok, new_state}

          result =~ "Interactive Elixir" ->
            {:reply, :node_started, state}

          result =~ "error" ->
            Logger.error(fn -> result end)
            {:reply, :error, state}

          true ->
            receive_result(state)
        end
    after
      1_000 ->
        {:reply, :different_res, state}
    end
  end

  def handle_call({:send_tokens, node1, node2, amount}, _, state) do
    sender = state[node1].miner_pubkey |> Account.base58c_encode
    receiver = state[node2].miner_pubkey |> Account.base58c_encode
    port = state[node1].process_port
    Port.command(port, "{_, sender_priv_key} = Keys.keypair(:sign)\n")
    Port.command(port, "pubkey_sender = \"#{sender}\"\n")
    Port.command(port, "pubkey_receiver = \"#{receiver}\"\n")
    Port.command(port, "nonce = Account.nonce(Chain.chain_state().accounts, Account.base58c_decode(pubkey_sender)) + 1\n")
    Port.command(port, "ttl = Chain.top_height() + 1\n")
    Port.command(port, "Account.spend(Account.base58c_decode(pubkey_sender), sender_priv_key, Account.base58c_decode(pubkey_receiver), #{amount}, 10, nonce, \"test1\")\n")
    {:reply, :ok, state}
  end

  def handle_call({:send_command, node_name, cmd}, _, state) do
    if Map.has_key?(state, node_name) do
      port = state[node_name].process_port
      Port.command(port, cmd)
      receive_result(state)
    else
      {:reply, :unknown_node, state}
    end
  end

  def handle_call({:get_balance, node}, _, state) do
    {:reply, state[node].miner_balance, state}
  end

  def handle_call({:update_pubkeys_state}, _, state) do
    new_state = Enum.reduce(state, state, fn(node, acc) ->
      {node_name, _} = node
      port = state[node_name].port
      {:ok, peer_info} = Client.get_info("localhost:#{port}")
      pubkey = peer_info.public_key
      put_in(acc[node_name].miner_pubkey, Account.base58c_decode(pubkey))
    end)

    {:reply, :ok, new_state}
  end

  def handle_call({:sync_two_nodes, node_name1, node_name2}, _, state) do
    port = state[node_name2].port
    sync_port = state[node_name2].sync_port

    cmd1 = "{:ok, peer_info} = Client.get_info(\"localhost:#{port}\")\n"
    Port.command(state[node_name1].process_port, cmd1)

    cmd2 = "pub_key = Map.get(peer_info, :peer_pubkey) |> Keys.peer_decode()\n"
    Port.command(state[node_name1].process_port, cmd2)

    cmd3 = "Peers.try_connect(%{host: 'localhost', port: #{sync_port}, pubkey: pub_key})\n"
    Port.command(state[node_name1].process_port, cmd3)

    {:reply, :ok, state}
  end

  def handle_call({:get_state}, _, state) do
    {:reply, state, state}
  end

  def handle_call({:delete_all_nodes}, _, state) do
    # killing all the processes and closing all of the ports of the nodes
    Enum.each(state, fn {_, val} ->
      Port.command(val.process_port, ":erlang.halt()\n")
      Port.close(val.process_port)
      path = String.replace(System.cwd(), ~r/(?<=elixir-node).*$/, "") <> "/apps/aecore/priv/"
      File.rm_rf(path <> "aewallet_#{val.port}")
      File.rm_rf(path <> "peerkeys_#{val.port}")
      File.rm_rf(path <> "rox_db_#{val.port}")
    end)

    {:reply, :ok, %{}}
  end

  def handle_call({:delete_node, node_name}, _, state) do
    if Map.has_key?(state, node_name) do
      Port.command(state[node_name].process_port, ":erlang.halt()\n")
      Port.close(state[node_name].process_port)
      new_state = Map.delete(state, node_name)
      {:reply, :ok, new_state}
    else
      {:reply, :unknown_node, state}
    end
  end

  def handle_call({:ports_info}, _, state) do
    ports_info = for {name, _} <- state, do: Port.info(state[name].process_port)
    {:reply, ports_info, state}
  end

  def handle_call(
        {:get_oracle_interaction_objects, node},
        _,
        state
      ) do
    {:reply, state[node].oracle_interaction_objects}
  end

  def handle_call({:get_top_block, node}, _, state) do
    {:reply, state[node].top_block, state}
  end

  def handle_call({:get_top_block_hash, node}, _, state) do
    {:reply, state[node].top_block_hash, state}
  end

  def handle_call({:new_node, node_name, iex_num}, _, state) do
    cond do
      Map.has_key?(state, node_name) ->
        {:reply, :already_exists, state}

      busy_port?("300#{iex_num}") || busy_port?("400#{iex_num}") ->
        {:reply, :busy_port, state}

      true ->
        # Running the new elixir-node using Port
        path = String.replace(System.cwd(), ~r/(?<=elixir-node).*$/, "")
        process_port = Port.open({:spawn, "make iex-node NODE_NUMBER=#{iex_num}"}, [:binary, cd: path])
        {:reply, :node_started, state} = receive_result(state)
        port = String.to_integer("400#{iex_num}")
        sync_port = String.to_integer("300#{iex_num}")

        new_state =
          Map.put(state, node_name, %{
            process_port: process_port,
            port: port,
            sync_port: sync_port,
            top_block: nil,
            top_block_hash: nil,
            miner_pubkey: nil,
            miner_balance: 0,
            peers: %{},
            oracle_interaction_objects: %{}
          })

        {:reply, :ok, new_state}
    end
  end
end
