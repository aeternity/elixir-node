defmodule Aetestframework.MultiNodeTestFramework.Worker do
  @moduledoc """
  Module for multi node sync test
  """

  alias Aeutil.Serialization
  alias Aehttpclient.Client
  alias Aecore.Account.Account
  alias String.Chars

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

  @doc """
    Updates top block state for 2 nodes and compares them.
    If top block of each node is equal - they are synced
  """
  @spec compare_nodes_by_top_block(String.t(), String.t()) :: :synced | :not_synced
  def compare_nodes_by_top_block(node_name1, node_name2) do
    get_node_top_block(node_name1)
    get_node_top_block(node_name2)
    GenServer.call(__MODULE__, {:compare_nodes_by_top_block, node_name1, node_name2})
  end

  @spec compare_nodes_by_top_block_hash(String.t(), String.t()) :: :synced | :not_synced
  def compare_nodes_by_top_block_hash(node_name1, node_name2) do
    get_node_top_block_hash(node_name1)
    get_node_top_block_hash(node_name2)
    GenServer.call(__MODULE__, {:compare_nodes_by_top_block_hash, node_name1, node_name2})
  end

  def compare_nodes_by_oracle_interaction_objects(node_name1, node_name2) do
    oracle_interaction_objects(node_name1)
    oracle_interaction_objects(node_name2)

    GenServer.call(
      __MODULE__,
      {:compare_nodes_by_oracle_interaction_objects, node_name1, node_name2}
    )
  end

  def update_top_block(new_top_block) do
    GenServer.call(__MODULE__, {:update_top_block, new_top_block})
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

  def send_tokens(node1, node2, amount) do
    GenServer.call(__MODULE__, {:send_tokens, node1, node2, amount})
  end

  def get_balance(node) do
    GenServer.call(__MODULE__, {:get_balance, node})
  end

  @doc """
    Kills the process, releases the port and removes the folder of the node
  """
  @spec delete_node(String.t()) :: :ok | :unknown_node
  def delete_node(node_name) do
    GenServer.call(__MODULE__, {:delete_node, node_name})
  end

  def delete_all_nodes do
    GenServer.call(__MODULE__, {:delete_all_nodes}, 20_000)
  end

  def busy_port?(port) do
    :os.cmd('lsof -i -P -n | grep -w #{port}') != []
  end

  defp update_data(state, result, node, :peers) do
    regex_res = Regex.run(~r/{(:respond_peers,) .*}/, result)
    res = List.first(regex_res)
    [host] = Regex.run(~r/(?<=host: )[^,]*/, res)
    [port] = Regex.run(~r/(?<=port: )[^,]*/, res)
    [pubkey] = Regex.run(~r/(?<=pubkey: )[^}]*/, res)
    formatted_host = host |> String.replace("\'", "") |> String.replace("\"", "")
    formatted_port = String.to_integer(port)
    formatted_pubkey = pubkey |> String.replace("\"", "") |> String.trim() |> Base.decode32!()

    peers_map = %{
      host: formatted_host,
      port: formatted_port,
      pubkey: formatted_pubkey
    }

    put_in(state[node].peers, peers_map)
  end

  defp update_data(state, result, respond, port, :top_block_hash) do
    {node, _} = Enum.find(state, fn {_, value} -> value.process_port == port end)
    one_line_res = String.replace(result, "\n", "")
    respond_res = Regex.run(~r/({#{respond}.*})/, one_line_res)
    res = Regex.run(~r/"(.*)"/, List.last(respond_res))
    base_decoded = Base.decode32!(List.last(res))
    put_in(state[node].top_block_hash, base_decoded)
  end

  defp update_data(state, result, respond, port, type) do
    {node, _} = Enum.find(state, fn {_, value} -> value.process_port == port end)
    one_line_res = String.replace(result, "\n", "")
    respond_res = Regex.run(~r/({#{respond}.*})/, one_line_res)
    res = Regex.run(~r/"(.*)"/, List.last(respond_res))
    base_decoded = Base.decode32!(List.last(res))

    if type == :oracle_interaction_objects do
      {:ok, rlp_decoded} = Serialization.rlp_decode(base_decoded)
    else
      rlp_decoded = Serialization.rlp_decode(base_decoded)
    end

    put_in(state[node][type], rlp_decoded)
  end

  def check_peers(state, node, result) do
    one_line_res = String.replace(result, "\n", "")
    if Regex.match?(~r/({:respond_peers, \[\])/, one_line_res) do
      state
    else
      update_data(state, one_line_res, node, :peers)
    end
  end

  def update_balance(node_name) do
    send_command(node_name, "pk = Wallet.get_public_key")
    send_command(node_name, "{:acc_balance, Account.balance(Chain.chain_state().accounts, pk)}")
    send_command(node_name, "")
  end

  # oracles
  @spec oracle_interaction_objects(String.t()) :: :ok | :unknown_node
  def oracle_interaction_objects(node_name) do
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
      "encoded_int_object = Serialization.rlp_encode(interaction_object, :oracle_query) |> Base.encode32"
    )

    send_command(
      node_name,
      "{:respond_oracle_int_obj, encoded_int_object}"
    )

    send_command(node_name, " ")
  end

  @doc """
    Functions to register, extend, query, respond oracles.
    They have already defined arguments taken from the tests
  """
  @spec register_oracle(String.t()) :: :ok | :unknown_node
  def register_oracle(node_name) do
    send_command(
      node_name,
      "Oracle.register(\"foo: bar\", \"foo: bar\", 5, 5, %{ttl: 10, type: :relative})"
    )
  end

  @spec extend_oracle(String.t()) :: :ok | :unknown_node
  def extend_oracle(node_name) do
    send_command(node_name, "Oracle.extend(3, 10)")
  end

  @spec query_oracle(String.t()) :: :ok | :unknown_node
  def query_oracle(node_name) do
    send_command(
      node_name,
      "oracle_tree = Chain.chain_state().oracles.oracle_tree"
    )

    send_command(
      node_name,
      "oracle_address = oracle_tree |> PatriciaMerkleTree.all_keys() |> List.first()"
    )

    send_command(
      node_name,
      "Oracle.query(oracle_address, \"foo: bar\", 5, 10, %{ttl: 10, type: :relative}, %{ttl: 10, type: :relative})"
    )
  end

  @spec respond_oracle(String.t()) :: :ok | :unknown_node
  def respond_oracle(node_name) do
    send_command(
      node_name,
      "oracle_tree = Chain.chain_state().oracles.oracle_tree"
    )

    send_command(
      node_name,
      "query_id = oracle_tree |> PatriciaMerkleTree.all_keys() |> List.last()"
    )

    send_command(node_name, "Oracle.respond(query_id, \"boolean\", 5)")
  end

  # spend_tx

  @spec spend_tx(String.t()) :: :ok | :unknown_node
  def spend_tx(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Account.spend(Wallet.get_public_key(\"M/0\"), 20, 10, \"test1\")"
    )

    send_command(node_name, "Pool.add_transaction(tx)")
  end

  # mining
  @spec mine_sync_block(String.t()) :: :ok | :unknown_node
  def mine_sync_block(node_name) do
    send_command(node_name, "Miner.mine_sync_block_to_chain()")
    update_balance(node_name)
  end

  # chain
  @spec get_node_top_block(String.t()) :: :ok | String.t()
  def get_node_top_block(node_name) do
    send_command(node_name, "top_block = Chain.top_block()")

    send_command(
      node_name,
      "rlp_top_block = Serialization.rlp_encode(top_block, :block)"
    )

    send_command(
      node_name,
      "{:respond_top_block, Base.encode32(rlp_top_block)}"
    )

    send_command(node_name, " ")

    # send_command(node_name, "{:respond_top_block, serialized_block}")
  end

  @spec get_node_top_block_hash(String.t()) :: :ok | :unknown_node
  def get_node_top_block_hash(node_name) do
    send_command(node_name, "block_hash = Chain.top_block_hash() |> Base.encode32")
    send_command(node_name, "{:respond_hash, block_hash}")
    send_command(node_name, " ")
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
      "{:ok, tx} = Account.pre_claim(\"test.aet\", <<1::256>>, 10)"
    )

    send_command(node_name, "Pool.add_transaction(tx)")
  end

  @spec naming_claim(String.t()) :: :ok | :unknown_node
  def naming_claim(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Account.claim(\"test.aet\", <<1::256>>, 10)"
    )

    send_command(node_name, "Pool.add_transaction(tx)")
  end

  @spec naming_update(String.t()) :: :ok | :unknown_node
  def naming_update(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Account.name_update(\"test.aet\", \"{\\\"test\\\":2}\", 10) "
    )

    send_command(node_name, "Pool.add_transaction(tx)")
  end

  @spec naming_transfer(String.t()) :: :ok | :unknown_node
  def naming_transfer(node_name) do
    send_command(node_name, "transfer_to_priv = Wallet.get_private_key(\"m/0/1\")")
    send_command(node_name, "transfer_to_pub = Wallet.to_public_key(transfer_to_priv)")

    send_command(
      node_name,
      "{:ok, transfer} = Account.name_transfer(\"test.aet\", transfer_to_pub, 10)"
    )

    send_command(node_name, "Pool.add_transaction(transfer)")
  end

  @spec naming_revoke(String.t()) :: :ok | :unknown_node
  def naming_revoke(node_name) do
    send_command(node_name, "transfer_to_priv = Wallet.get_private_key(\"m/0/1\")")
    send_command(node_name, "transfer_to_pub = Wallet.to_public_key(transfer_to_priv)")

    send_command(
      node_name,
      "{:ok, spend} = Account.spend(transfer_to_pub, 15, 10, <<\"payload\">>)"
    )

    send_command(node_name, "Pool.add_transaction(spend)")
    mine_sync_block(node_name)

    send_command(
      node_name,
      "next_nonce = Account.nonce(Chain.chain_state().accounts, transfer_to_pub) + 1"
    )

    send_command(
      node_name,
      "{:ok, revoke} = Account.name_revoke(transfer_to_pub, transfer_to_priv, \"test.aet\", 10, next_nonce)"
    )

    send_command(node_name, "Pool.add_transaction(revoke)")
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

    send_command(
      node_name,
      "peers_encoded = Enum.reduce(peers, [], fn peer, acc ->
                                acc ++ [put_in(peer.pubkey, Base.encode32(peer.pubkey))]
                              end)"
    )

    send_command(node_name, "{:respond_peers, peers_encoded}")
  end

  # server

  def handle_info(result, state) do
    IO.puts "______________"
    IO.inspect result
    IO.puts "______________"
    {:noreply, state}
  end

  def receive_result(state) do
    receive do
      {port, {:data, result}} ->
        cond do
          result =~ ":respond_top_block" ->
            new_state = update_data(state, result, ":respond_top_block", port, :top_block)
            {:reply, :ok, new_state}

          result =~ ":respond_hash" ->
            new_state = update_data(state, result, ":respond_hash", port, :top_block_hash)
            {:reply, :ok, new_state}

          result =~ ":respond_oracle_int_obj" ->
            new_state = update_data(state, result, ":respond_oracle_int_obj", port, :oracle_interaction_objects)
            {:reply, :ok, new_state}

          result =~ ":respond_peers" ->
            {node, _} = Enum.find(state, fn {_, value} -> value.process_port == port end)
            new_state = check_peers(state, node, result)
            {:reply, :ok, new_state}

          result =~ ":acc_balance" ->
            {node, _} = Enum.find(state, fn {_, value} -> value.process_port == port end)
            balance_str = Regex.run(~r/\d+/, result)
            {balance, _} = balance_str |> List.first() |> Integer.parse()
            new_state = put_in(state[node].miner_balance, balance)
            {:reply, result, new_state}

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
    Port.command(port, "sender_priv_key = Wallet.get_private_key()\n")
    Port.command(port, "pubkey_sender = \"#{sender}\"\n")
    Port.command(port, "pubkey_receiver = \"#{receiver}\"\n")
    Port.command(port, "nonce = Account.nonce(Chain.chain_state().accounts, Account.base58c_decode(pubkey_sender)) + 1\n")
    Port.command(port, "ttl = Chain.top_height() + 1\n")
    Port.command(port, "{:ok, tx} = Account.spend(Account.base58c_decode(pubkey_sender), sender_priv_key, Account.base58c_decode(pubkey_receiver), #{amount}, 10, nonce, \"test1\", 20)\n")
    Port.command(port, "Pool.add_transaction(tx)\n")

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

    cmd2 = "pub_key = Map.get(peer_info, :peer_pubkey) |> PeerKeys.base58c_decode()\n"
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
      port = val.port
      Port.close(val.process_port)
      pid_str = :os.cmd('lsof -ti tcp:#{port}')
      pid = pid_str |> Chars.to_string() |> String.trim()
      System.cmd("kill", ["-9", pid])
      path = String.replace(System.cwd(), ~r/(?<=elixir-node).*$/, "") <> "/apps/aecore/priv/"
      File.rm_rf(path <> "aewallet_#{val.port}")
      File.rm_rf(path <> "peerkeys_#{val.port}")
      File.rm_rf(path <> "rox_db_#{val.port}")
    end)

    {:reply, :ok, %{}}
  end

  def handle_call({:delete_node, node_name}, _, state) do
    if Map.has_key?(state, node_name) do
      # kills the process, closes the port
      port = state[node_name].port
      Port.close(state[node_name].process_port)
      pid_str = :os.cmd('lsof -ti tcp:#{port}')
      pid = pid_str |> Chars.to_string() |> String.trim()
      System.cmd("kill", ["-9", pid])
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
        {:compare_nodes_by_oracle_interaction_objects, node_name1, node_name2},
        _,
        state
      ) do
    oracle_interaction_objects1 = state[node_name1].oracle_interaction_objects
    oracle_interaction_objects2 = state[node_name2].oracle_interaction_objects

    if oracle_interaction_objects1 == oracle_interaction_objects2 do
      {:reply, :synced, state}
    else
      {:reply, :not_synced, state}
    end
  end

  def handle_call({:compare_nodes_by_top_block, node_name1, node_name2}, _, state) do
    block1 = state[node_name1].top_block
    block2 = state[node_name2].top_block

    if block1 != nil && block2 != nil && block1 == block2 do
      {:reply, :synced, state}
    else
      {:reply, :not_synced, state}
    end
  end

  def handle_call({:compare_nodes_by_top_block_hash, node_name1, node_name2}, _, state) do
    hash1 = state[node_name1].top_block_hash
    hash2 = state[node_name2].top_block_hash

    if hash1 != nil && hash2 != nil && hash1 == hash2 do
      {:reply, :synced, state}
    else
      {:reply, :not_synced, state}
    end
  end

  def handle_call({:new_node, node_name, iex_num}, _, state) do
    cond do
      Map.has_key?(state, node_name) ->
        {:reply, :already_exists, state}

      busy_port?("300#{iex_num}") || busy_port?("400#{iex_num}") ->
        {:reply, :busy_port, state}

      true ->
        # Running the new elixir-node using Port
        IO.inspect System.cwd()
        path = String.replace(System.cwd(), ~r/(?<=elixir-node).*$/, "")
        proc = Porcelain.spawn_shell("make iex-node NODE_NUMBER=#{iex_num}", dir: path, in: :receive, out: {:send, self()})

        # process_port = Port.open({:spawn, "make iex-node NODE_NUMBER=#{iex_num}"}, [:binary, cd: path])
        port = String.to_integer("400#{iex_num}")
        sync_port = String.to_integer("300#{iex_num}")

        new_state =
          Map.put(state, node_name, %{
            # process_port: process_port,
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
