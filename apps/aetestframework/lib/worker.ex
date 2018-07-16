defmodule Aetestframework.MultiNodeTestFramework.Worker do
  @moduledoc """
  Module for multi node sync test
  """

  alias Aeutil.Serialization

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
    get_all_peers(node_name1)
    get_all_peers(node_name2)
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

  @doc """
    Updates registered oracles state for 2 nodes and compares them.
    If registered oracles are equal - they are synced
  """
  def compare_nodes_by_registered_oracles(node_name1, node_name2) do
    registered_oracles(node_name1)
    registered_oracles(node_name2)
    GenServer.call(__MODULE__, {:compare_nodes_by_registered_oracles, node_name1, node_name2})
  end

  def compare_nodes_by_oracle_interaction_objects(node_name1, node_name2) do
    oracle_interaction_objects(node_name1)
    oracle_interaction_objects(node_name2)

    GenServer.call(
      __MODULE__,
      {:compare_nodes_by_oracle_interaction_objects, node_name1, node_name2}
    )
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
    GenServer.call(__MODULE__, {:send_command, node_name, cmd})
  end

  @spec get_pool(String.t()) :: :ok | :unknown_node
  def get_pool(node_name) do
    send_command(node_name, "Pool.get_pool()")
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

  defp update_registered_oracles_state(node_name) do
    GenServer.call(__MODULE__, {:update_registered_oracles_state, node_name})
  end

  defp update_oracle_interaction_objects_state(node_name) do
    GenServer.call(__MODULE__, {:update_oracle_interaction_objects_state, node_name})
  end

  @spec update_top_block_state(String.t()) :: :ok | String.t()
  defp update_top_block_state(node_name) do
    GenServer.call(__MODULE__, {:update_top_block_state, node_name})
  end

  @spec update_peers_map(String.t()) :: :ok
  defp update_peers_map(node_name) do
    GenServer.call(__MODULE__, {:update_peers_map, node_name})
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

    # encoding the map to the json
    send_command(node_name, "{:ok, json} = Poison.encode(encoded_int_object)")

    # writing it to the file
    send_command(node_name, "File.write(System.cwd() <> \"/result.json\", json)")

    # updating the state of the oracle interaction objects after the one second
    :timer.sleep(1000)
    update_oracle_interaction_objects_state(node_name)
  end

  @spec registered_oracles(String.t()) :: :ok | :unknown_node
  def registered_oracles(node_name) do
    send_command(node_name, "oracle_tree = Chain.chain_state().oracles.oracle_tree")

    # converting the keys which are binary to string
    send_command(
      node_name,
      "oracles_for_encoding = for {k,v} <- registered_oracles, into: %{}, do: {Base.encode32(k), v}"
    )

    # converting the keys which are binary to string in a nested map
    send_command(
      node_name,
      "oracles_encoded = Enum.reduce(oracles_for_encoding, %{}, fn {k, val}, acc ->
                                put_in(oracles_for_encoding[k].owner, Base.encode32(val.owner))
                              end)"
    )

    # encoding the map to the json
    send_command(node_name, "{:ok, json} = Poison.encode(oracles_encoded)")

    # writing it to the file
    send_command(node_name, "File.write(System.cwd() <> \"/result.json\", json)")

    # updating the state of the oracle interaction objects after the one second
    :timer.sleep(1000)
    update_registered_oracles_state(node_name)
  end

  @doc """
    Functions to register, extend, query, respond oracles.
    They have already defined arguments taken from the tests
  """
  @spec register_oracle(String.t()) :: :ok | :unknown_node
  def register_oracle(node_name) do
    send_command(
      node_name,
      "Oracle.register(%{\"type\" => \"object\", \"properties\" => %{\"currency\" => %{\"type\" => \"string\"}}}, %{\"type\" => \"object\", \"properties\" => %{\"currency\" => %{\"type\" => \"string\"}}}, 5, 5, %{:ttl => 10, :type => :relative})"
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
      "Oracle.query(oracle_address, %{\"currency\" => \"USD\"}, 5, 10, %{:ttl => 10, :type => :relative}, %{:ttl => 10, :type => :relative})"
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

    send_command(node_name, "Oracle.respond(query_id, %{\"currency\" => \"BGN\"}, 5)")
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
    get_node_top_block(node_name)
  end

  # chain
  @spec get_node_top_block(String.t()) :: :ok | String.t()
  def get_node_top_block(node_name) do
    send_command(node_name, "top_block = Chain.top_block()")

    send_command(
      node_name,
      "serialized_block = Serialization.rlp_encode(top_block, :block) |> Base.encode32()"
    )

    send_command(node_name, "{:ok, json} = Poison.encode(serialized_block)")

    send_command(
      node_name,
      "File.write((String.replace(System.cwd(), ~r/(?<=elixir-node).*$/, \"\")) <> \"/result.json\", json)"
    )

    :timer.sleep(2000)
    update_top_block_state(node_name)
  end

  @spec get_node_top_block_hash(String.t()) :: :ok | :unknown_node
  def get_node_top_block_hash(node_name) do
    send_command(node_name, "block_hash = Chain.top_block_hash() |> Base.encode32")
    send_command(node_name, "{:block_hash, block_hash}")
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
    send_command(node_name, "Chain.chain_state().naming")
  end

  @doc """
    Gets all peers for a given node
  """
  @spec get_all_peers(String.t()) :: :ok
  def get_all_peers(node_name) do
    send_command(node_name, "peers = Peers.all_peers")

    send_command(
      node_name,
      "peers_encoded = Enum.reduce(peers, [], fn (peer), acc ->
                                acc ++ [put_in(peer.pubkey, Base.encode32(peer.pubkey))]
                              end)"
    )

    # encoding the peers map to the json
    send_command(node_name, "{:ok, json} = Poison.encode(peers_encoded)")

    # writing the json to the file
    send_command(node_name, "File.write(System.cwd() <> \"/result.json\", json)")

    # updating peers map in the state after 1 second
    :timer.sleep(1000)
    update_peers_map(node_name)
  end

  def busy_port?(port) do
    :os.cmd('lsof -i -P -n | grep -w #{port}') != []
  end

  defp update_data(fun, state, node_name, key) do
    with true <- Map.has_key?(state, node_name),
         path <- String.replace(System.cwd(), ~r/(?<=elixir-node).*$/, ""),
         file <- path <> "/result.json",
         {:ok, data} <- File.read(file),
         {:ok, decoded_data} <- Poison.decode(data) do
      # decoding all the keys and the data to it's initial state
      decoded_data = fun.(decoded_data)

      # updating the state and removing the json file
      new_state = put_in(state[node_name][key], decoded_data)
      File.rm(file)
      {:reply, :ok, new_state}
    else
      false -> {:reply, :no_such_node, state}
      {:error, reason} -> {:reply, reason, state}
    end
  end

  # server

  def handle_info({_, {:data, result}}, state) do
    if String.match?(result, ~r/error/) do
      Logger.error(fn -> result end)
    end

    {:noreply, state}
  end

  def handle_call({:update_oracle_interaction_objects_state, node_name}, _, state) do
    fun = fn decoded_data ->
      {:ok, int_obj} =
        decoded_data
        |> Base.decode32!()
        |> Serialization.rlp_decode()

      int_obj
    end

    update_data(fun, state, node_name, :oracle_interaction_objects)
  end

  def handle_call({:update_registered_oracles_state, node_name}, _, state) do
    fun = fn decoded_data ->
      oracles_decode32 = for {k, v} <- decoded_data, into: %{}, do: {Base.decode32!(k), v}

      Enum.reduce(oracles_decode32, %{}, fn {k, val}, _ ->
        atom_keys_map = for {nested_k, v} <- val, into: %{}, do: {String.to_atom(nested_k), v}
        new_map = put_in(oracles_decode32[k], atom_keys_map)
        put_in(new_map[k].owner, Base.decode32!(new_map[k].owner))
      end)
    end

    update_data(fun, state, node_name, :registered_oracles)
  end

  def handle_call({:update_top_block_state, node_name}, _, state) do
    fun = fn decoded_data ->
      decoded_data
      |> Base.decode32!()
      |> Serialization.rlp_decode()
    end

    update_data(fun, state, node_name, :top_block)
  end

  def handle_call({:update_peers_map, node_name}, _, state) do
    fun = fn decoded_data ->
      Enum.reduce(decoded_data, [], fn peer, acc ->
        peer =
          for {k, v} <- peer,
              into: %{},
              do: {String.to_atom(k), v}

        peer = put_in(peer.pubkey, Base.decode32!(peer.pubkey))
        [peer | acc]
      end)
    end

    update_data(fun, state, node_name, :peers)
  end

  def handle_call({:send_command, node_name, cmd}, _, state) do
    if Map.has_key?(state, node_name) do
      Port.command(state[node_name].process_port, cmd)
      {:reply, :ok, state}
    else
      {:reply, :unknown_node, state}
    end
  end

  def handle_call({:sync_two_nodes, node_name1, node_name2}, _, state) do
    port = state[node_name2].port
    sync_port = state[node_name2].sync_port

    cmd = "{:ok, peer_info} = Client.get_info(\"localhost:#{port}\")\n"
    Port.command(state[node_name1].process_port, cmd)

    cmd = "pub_key = Map.get(peer_info, :peer_pubkey) |> PeerKeys.base58c_decode()\n"
    Port.command(state[node_name1].process_port, cmd)

    cmd = "Peers.try_connect(%{host: 'localhost', port: #{sync_port}, pubkey: pub_key})\n"
    Port.command(state[node_name1].process_port, cmd)
    {:reply, :ok, state}
  end

  def handle_call({:get_state}, _, state) do
    {:reply, state, state}
  end

  def handle_call({:delete_all_nodes}, _, state) do
    # killing all the processes and closing all of the ports of the nodes
    Enum.each(state, fn {_, val} ->
      {:os_pid, pid} = Port.info(val.process_port, :os_pid)
      Port.close(val.process_port)
      System.cmd("kill", ["-9", "#{pid}"])
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
      {:os_pid, pid} = Port.info(state[node_name].process_port, :os_pid)
      Port.close(state[node_name].process_port)

      System.cmd("kill", ["#{pid}"])
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

  def handle_call({:compare_nodes_by_registered_oracles, node_name1, node_name2}, _, state) do
    registered_oracles1 = state[node_name1].registered_oracles
    registered_oracles2 = state[node_name2].registered_oracles

    if registered_oracles1 == registered_oracles2 do
      {:reply, :synced, state}
    else
      {:reply, :not_synced, state}
    end
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

    if block1 == block2 do
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
        path = String.replace(System.cwd(), ~r/(?<=elixir-node).*$/, "")
        process_port = Port.open({:spawn, "make iex-n IEX_NUM=#{iex_num}"}, [:binary, cd: path])
        port = String.to_integer("400#{iex_num}")
        sync_port = String.to_integer("300#{iex_num}")

        new_state =
          Map.put(state, node_name, %{
            process_port: process_port,
            port: port,
            sync_port: sync_port,
            top_block: nil,
            peers: %{},
            registered_oracles: %{},
            oracle_interaction_objects: %{}
          })

        {:reply, :ok, new_state}
    end
  end
end
