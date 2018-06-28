defmodule Aecore.MultiNodeTestFramework.Worker do
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
  def new_node(node_name, port) do
    GenServer.call(__MODULE__, {:new_node, node_name, port})
  end

  @spec sync_two_nodes(String.t(), String.t()) :: :ok
  def sync_two_nodes(node_name1, node_name2) do
    GenServer.call(__MODULE__, {:sync_two_nodes, node_name1, node_name2})
    get_all_peers(node_name1)
    get_all_peers(node_name2)
  end

  @spec compare_nodes_by_top_block(String.t(), String.t()) :: :synced | :not_synced
  def compare_nodes_by_top_block(node_name1, node_name2) do
    get_node_top_block(node_name1)
    get_node_top_block(node_name2)
    GenServer.call(__MODULE__, {:compare_nodes_by_top_block, node_name1, node_name2})
  end

  def compare_nodes_by_registered_oracles(node_name1, node_name2) do
    registered_oracles(node_name1)
    registered_oracles(node_name2)
    GenServer.call(__MODULE__, {:compare_nodes_by_registered_oracles, node_name1, node_name2})
  end

  def alive_ports do
    GenServer.call(__MODULE__, {:alive_ports})
  end

  @spec send_command(String.t(), String.t()) :: :ok | :unknown_node
  def send_command(node_name, cmd) do
    cmd = cmd <> "\n"
    GenServer.call(__MODULE__, {:send_command, node_name, cmd})
  end

  @spec get_pool(String.t()) :: :ok | :unknown_node
  def get_pool(node_name) do
    send_command(node_name, "Aecore.Tx.Pool.Worker.get_pool()")
  end

  @spec delete_node(String.t()) :: :ok | :unknown_node
  def delete_node(node_name) do
    GenServer.call(__MODULE__, {:delete_node, node_name})
  end

  def delete_all_nodes do
    GenServer.call(__MODULE__, {:delete_all_nodes})
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
    send_command(node_name, "int_object = Aecore.Chain.Worker.oracle_interaction_objects()")

    send_command(
      node_name,
      "oracle_int_obj_for_encoding = for {k,v} <- int_object, into: %{}, do: {Base.encode32(k), v}"
    )

    send_command(
      node_name,
      "oracles_encoded = Enum.reduce(oracle_int_obj_for_encoding, %{}, fn {k, val}, acc ->
                                new_oracles = put_in(oracle_int_obj_for_encoding[k].sender_address, Base.encode32(val.sender_address))
                                put_in(new_oracles[k].oracle_address, Base.encode32(val.oracle_address)) end)"
    )

    send_command(node_name, "{:ok, json} = Poison.encode(oracles_encoded)")
    send_command(node_name, "path = System.cwd() <> \"/result.json\"")
    send_command(node_name, "File.write(path, json)")
    :timer.sleep(1000)
    update_oracle_interaction_objects_state(node_name)
  end

  @spec registered_oracles(String.t()) :: :ok | :unknown_node
  def registered_oracles(node_name) do
    send_command(node_name, "registered_oracles = Aecore.Chain.Worker.registered_oracles()")

    send_command(
      node_name,
      "oracles_for_encoding = for {k,v} <- registered_oracles, into: %{}, do: {Base.encode32(k), v}"
    )

    send_command(
      node_name,
      "oracles_encoded = Enum.reduce(oracles_for_encoding, %{}, fn {k, val}, acc ->
                                put_in(oracles_for_encoding[k].owner, Base.encode32(val.owner))
                              end)"
    )

    send_command(node_name, "{:ok, json} = Poison.encode(oracles_encoded)")
    send_command(node_name, "path = System.cwd() <> \"/result.json\"")
    send_command(node_name, "File.write(path, json)")
    :timer.sleep(1000)
    update_registered_oracles_state(node_name)
  end

  @spec register_oracle(String.t()) :: :ok | :unknown_node
  def register_oracle(node_name) do
    send_command(
      node_name,
      "Aecore.Oracle.Oracle.register(%{\"type\" => \"object\", \"properties\" => %{\"currency\" => %{\"type\" => \"string\"}}}, %{\"type\" => \"object\", \"properties\" => %{\"currency\" => %{\"type\" => \"string\"}}}, 5, 5, %{:ttl => 10, :type => :relative})"
    )
  end

  @spec extend_oracle(String.t()) :: :ok | :unknown_node
  def extend_oracle(node_name) do
    send_command(node_name, "Aecore.Oracle.Oracle.extend(3, 10)")
  end

  @spec query_oracle(String.t()) :: :ok | :unknown_node
  def query_oracle(node_name) do
    send_command(
      node_name,
      "oracle = Aecore.Chain.Worker.registered_oracles() |> Map.keys() |> Enum.at(0)"
    )

    send_command(
      node_name,
      "Aecore.Oracle.Oracle.query(oracle, %{\"currency\" => \"USD\"}, 5, 10, %{:ttl => 10, :type => :relative}, %{:ttl => 10, :type => :relative})"
    )
  end

  @spec respond_oracle(String.t()) :: :ok | :unknown_node
  def respond_oracle(node_name) do
    send_command(
      node_name,
      "oracle = Aecore.Chain.Worker.oracle_interaction_objects() |> Map.keys() |> Enum.at(0)"
    )

    send_command(node_name, "Aecore.Oracle.Oracle.respond(oracle, %{\"currency\" => \"BGN\"}, 5)")
  end

  # spend_tx

  @spec spend_tx(String.t()) :: :ok | :unknown_node
  def spend_tx(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Aecore.Account.Account.spend(Aecore.Wallet.Worker.get_public_key(\"M/0\"), 20, 10, \"test1\")"
    )

    send_command(node_name, "Aecore.Tx.Pool.Worker.add_transaction(tx)")
  end

  # mining
  @spec mine_sync_block(String.t()) :: :ok | :unknown_node
  def mine_sync_block(node_name) do
    send_command(node_name, "Aecore.Miner.Worker.mine_sync_block_to_chain()")
    get_node_top_block(node_name)
  end

  # chain
  @spec get_node_top_block(String.t()) :: :ok | String.t()
  def get_node_top_block(node_name) do
    send_command(node_name, "top_block = Aecore.Chain.Worker.top_block()")

    send_command(
      node_name,
      "serialized_block = Aeutil.Serialization.block(top_block, :serialize)"
    )

    send_command(node_name, "{:ok, json} = Poison.encode(serialized_block)")
    send_command(node_name, "path = System.cwd() <> \"/result.json\"")
    send_command(node_name, "File.write(path, json)")
    :timer.sleep(2000)
    update_top_block_state(node_name)
  end

  @spec get_node_top_block_hash(String.t()) :: :ok | :unknown_node
  def get_node_top_block_hash(node_name) do
    send_command(node_name, "block_hash = Aecore.Chain.Worker.top_block_hash() |> Base.encode32")
    send_command(node_name, "{:block_hash, block_hash}")
  end

  # naming txs

  @spec naming_pre_claim(String.t()) :: :ok | :unknown_node
  def naming_pre_claim(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Aecore.Account.Account.pre_claim(\"test.aet\", <<1::256>>, 10)"
    )

    send_command(node_name, "Aecore.Tx.Pool.Worker.add_transaction(tx)")
  end

  @spec naming_claim(String.t()) :: :ok | :unknown_node
  def naming_claim(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Aecore.Account.Account.claim(\"test.aet\", <<1::256>>, 10)"
    )

    send_command(node_name, "Aecore.Tx.Pool.Worker.add_transaction(tx)")
  end

  @spec naming_update(String.t()) :: :ok | :unknown_node
  def naming_update(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Aecore.Account.Account.name_update(\"test.aet\", \"{\\\"test\\\":2}\", 10) "
    )

    send_command(node_name, "Aecore.Tx.Pool.Worker.add_transaction(tx)")
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

    send_command(node_name, "Aecore.Tx.Pool.Worker.add_transaction(revoke)")
  end

  @spec chainstate_naming(String.t()) :: :ok | :unknown_node
  def chainstate_naming(node_name) do
    send_command(node_name, "Aecore.Chain.Worker.chain_state().naming")
  end

  @spec alive_process_port?(String.t()) :: boolean()
  def alive_process_port?(process_port) do
    Port.info(process_port) != nil
  end

  @spec get_all_peers(String.t()) :: :ok
  def get_all_peers(node_name) do
    send_command(node_name, "peers = Aecore.Peers.Worker.all_peers")
    send_command(node_name, "{:ok, json} = Poison.encode(peers)")
    send_command(node_name, "path = System.cwd() <> \"/result.json\"")
    send_command(node_name, "File.write(path, json)")
    :timer.sleep(1000)
    update_peers_map(node_name)
  end

  def busy_port?(port) do
    :os.cmd('lsof -i -P -n | grep -w #{port}') != []
  end

  # server

  def handle_info({_, {:data, _}}, state) do
    {:noreply, state}
  end

  def handle_call({:update_oracle_interaction_objects_state, node_name}, _, state) do
    path = state[node_name].path <> "/result.json"

    with {:ok, data} <- File.read(path),
         {:ok, decoded_data} <- Poison.decode(data) do
      oracles_decode32 = for {k, v} <- decoded_data, into: %{}, do: {Base.decode32!(k), v}

      decoded_data =
        Enum.reduce(oracles_decode32, %{}, fn {k, val}, _ ->
          atom_keys_map = for {nested_k, v} <- val, into: %{}, do: {String.to_atom(nested_k), v}
          new_map = put_in(oracles_decode32[k], atom_keys_map)
          new_map = put_in(new_map[k].oracle_address, Base.decode32!(new_map[k].oracle_address))
          put_in(new_map[k].sender_address, Base.decode32!(new_map[k].sender_address))
        end)

      new_state = put_in(state[node_name].oracle_interaction_objects, decoded_data)
      File.rm(path)
      {:reply, :ok, new_state}
    else
      {:error, reason} -> {:reply, reason, state}
    end
  end

  def handle_call({:update_registered_oracles_state, node_name}, _, state) do
    path = state[node_name].path <> "/result.json"

    with {:ok, data} <- File.read(path),
         {:ok, decoded_data} <- Poison.decode(data) do
      oracles_decode32 = for {k, v} <- decoded_data, into: %{}, do: {Base.decode32!(k), v}

      decoded_data =
        Enum.reduce(oracles_decode32, %{}, fn {k, val}, _ ->
          atom_keys_map = for {nested_k, v} <- val, into: %{}, do: {String.to_atom(nested_k), v}
          new_map = put_in(oracles_decode32[k], atom_keys_map)
          put_in(new_map[k].owner, Base.decode32!(new_map[k].owner))
        end)

      new_state = put_in(state[node_name].registered_oracles, decoded_data)
      File.rm(path)
      {:reply, :ok, new_state}
    else
      {:error, reason} -> {:reply, reason, state}
    end
  end

  def handle_call({:update_top_block_state, node_name}, _, state) do
    with true <- Map.has_key?(state, node_name),
         path <- state[node_name].path <> "/result.json",
         {:ok, data} <- File.read(path),
         {:ok, decoded_data} <- Poison.decode(data) do
      serialized_block = Serialization.block(decoded_data, :deserialize)
      new_state = put_in(state[node_name].top_block, serialized_block)
      File.rm(path)
      {:reply, :ok, new_state}
    else
      false -> {:reply, :no_such_node, state}
      {:error, reason} -> {:reply, reason, state}
    end
  end

  def handle_call({:update_peers_map, node_name}, _, state) do
    with true <- Map.has_key?(state, node_name),
         path <- state[node_name].path <> "/result.json",
         {:ok, data} <- File.read(path),
         {:ok, decoded_data} <- Poison.decode(data) do
      decoded_data =
        Enum.reduce(decoded_data, %{}, fn {num, info}, acc ->
          info =
            for {k, v} <- info,
                into: %{},
                do: {String.to_atom(k), v}

          Map.put(acc, String.to_integer(num), info)
        end)

      new_state = put_in(state[node_name].peers, decoded_data)
      File.rm(path)
      {:reply, :ok, new_state}
    else
      false -> {:reply, :no_such_node, state}
      {:error, reason} -> {:reply, reason, state}
    end
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
    cmd = "Aecore.Peers.Worker.add_peer(\"localhost:#{port}\")\n"
    Port.command(state[node_name1].process_port, cmd)
    {:reply, :ok, state}
  end

  def handle_call({:get_state}, _, state) do
    {:reply, state, state}
  end

  def handle_call({:delete_all_nodes}, _, state) do
    Enum.each(state, fn {_, val} ->
      {:os_pid, pid} = Port.info(val.process_port, :os_pid)
      Port.close(val.process_port)
      System.cmd("kill", ["#{pid}"])

      val.path
      |> String.replace("elixir-node", "")
      |> File.rm_rf()
    end)

    {:reply, :ok, %{}}
  end

  def handle_call({:delete_node, node_name}, _, state) do
    if Map.has_key?(state, node_name) do
      {:os_pid, pid} = Port.info(state[node_name].process_port, :os_pid)
      Port.close(state[node_name].process_port)
      System.cmd("kill", ["#{pid}"])
      new_state = Map.delete(state, node_name)
      {:reply, :ok, new_state}
    else
      {:reply, :unknown_node, state}
    end
  end

  def handle_call({:alive_ports}, _, state) do
    alive_ports = for {name, _} <- state, do: Port.info(state[name].process_port)
    {:reply, alive_ports, state}
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

  def handle_call({:compare_nodes_by_top_block, node_name1, node_name2}, _, state) do
    block1 = state[node_name1].top_block
    block2 = state[node_name2].top_block

    if block1 == block2 do
      {:reply, :synced, state}
    else
      {:reply, :not_synced, state}
    end
  end

  def handle_call({:new_node, node_name, port}, _, state) do
    cond do
      Map.has_key?(state, node_name) ->
        {:reply, :already_exists, state}

      busy_port?(port) ->
        {:reply, :busy_port, state}

      true ->
        {:ok, tmp_path} = Temp.mkdir(node_name)
        path = String.replace(System.cwd(), ~r/(?<=elixir-node).*$/, "")
        System.cmd("cp", ["-R", path, tmp_path])
        tmp_path = tmp_path <> "/elixir-node"

        System.cmd("sed", [
          "-i",
          "s/4000/#{port}/",
          Path.join(tmp_path, "apps/aehttpserver/config/dev.exs")
        ])

        System.cmd("sed", [
          "-i",
          "s/4000/#{port}/",
          Path.join(tmp_path, "apps/aehttpserver/config/test.exs")
        ])

        process_port = Port.open({:spawn, "iex -S mix phx.server"}, [:binary, cd: tmp_path])

        new_state =
          Map.put(state, node_name, %{
            process_port: process_port,
            path: tmp_path,
            port: port,
            top_block: nil,
            top_block_hash: nil,
            peers: %{},
            registered_oracles: %{},
            oracle_interaction_objects: %{}
          })

        {:reply, :ok, new_state}
    end
  end
end
