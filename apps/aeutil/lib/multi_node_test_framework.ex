defmodule Aeutil.MultiNodeTestFramework do
  use GenServer

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def get_state() do
    GenServer.call(__MODULE__, {:get_state})
  end

  def new_node(port) do
    GenServer.call(__MODULE__, {:new_node, port})
  end

  def sync_two_nodes(node_name1, node_name2) do
    GenServer.call(__MODULE__, {:sync_two_nodes, node_name1, node_name2})
  end

  def alive_ports() do
    GenServer.call(__MODULE__, {:alive_ports})
  end

  def send_command(node_name, cmd) do
    cmd = cmd <> "\n"
    GenServer.call(__MODULE__, {:send_command, node_name, cmd})
  end

  def get_pool(node_name) do
    send_command(node_name, "Aecore.Tx.Pool.Worker.get_pool()")
  end

  # oracles
  def oracle_interaction_objects(node_name) do
    send_command(node_name, "Aecore.Chain.Worker.oracle_interaction_objects()")
  end

  def registered_oracles(node_name) do
    send_command(node_name, "Aecore.Chain.Worker.registered_oracles()")
  end

  def extend_oracle(node_name) do
    send_command(node_name, "Aecore.Oracle.Oracle.extend(3, 10)")
  end

  def register_oracle(node_name) do
    send_command(
      node_name,
      "Aecore.Oracle.Oracle.register(%{\"type\" => \"object\", \"properties\" =>
    %{\"currency\" => %{\"type\" => \"string\"}}},
    %{\"type\" => \"object\", \"properties\" => %{\"currency\" => %{\"type\" => \"string\"}}}, 5, 5,
    %{:ttl => 10, :type => :relative})"
    )
  end

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

  def respond_oracle(node_name) do
    send_command(
      node_name,
      "oracle = Aecore.Chain.Worker.oracle_interaction_objects() |> Map.keys() |> Enum.at(0)"
    )

    send_command(node_name, "Aecore.Oracle.Oracle.respond(oracle, %{\"currency\" => \"BGN\"}, 5)")
  end

  # spend_tx
  def spend_tx(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Aecore.Account.Account.spend(Aecore.Wallet.Worker.get_public_key(\"M/0\"), 20, 10, \"test1\")"
    )

    send_command(node_name, "Aecore.Tx.Pool.Worker.add_transaction(tx)")
  end

  # mining
  def mine_sync_block(node_name) do
    send_command(node_name, "Aecore.Miner.Worker.mine_sync_block_to_chain()")
  end

  # chain
  def get_node_top_block(node_name) do
    send_command(node_name, "Aecore.Chain.Worker.top_block()")
  end

  # naming txs
  def naming_pre_claim(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Aecore.Account.Account.pre_claim(\"test.aet\", <<1::256>>, 10)"
    )

    send_command(node_name, "Aecore.Tx.Pool.Worker.add_transaction(tx)")
  end

  def naming_claim(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Aecore.Account.Account.claim(\"test.aet\", <<1::256>>, 10)"
    )

    send_command(node_name, "Aecore.Tx.Pool.Worker.add_transaction(tx)")
  end

  def naming_update(node_name) do
    send_command(
      node_name,
      "{:ok, tx} = Aecore.Account.Account.name_update(\"test.aet\", \"{\\\"test\\\":2}\", 10) "
    )

    send_command(node_name, "Aecore.Tx.Pool.Worker.add_transaction(tx)")
  end

  def naming_transfer(node_name) do
    send_command(node_name, "transfer_to_priv = Wallet.get_private_key(\"m/0/1\")")
    send_command(node_name, "transfer_to_pub = Wallet.to_public_key(transfer_to_priv)")

    send_command(
      node_name,
      "{:ok, transfer} = Account.name_transfer(\"test.aet\", transfer_to_pub, 10)"
    )

    send_command(node_name, "Pool.add_transaction(transfer)")
  end

  def naming_revoke(node_name) do
    send_command(node_name, "transfer_to_priv = Wallet.get_private_key(\"m/0/1\")")
    send_command(node_name, "transfer_to_pub = Wallet.to_public_key(transfer_to_priv)")

    send_command(
      node_name,
      "{:ok, spend} = Account.spend(transfer_to_pub, 5, 10, <<\"payload\">>)"
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

  def chainstate_naming(node_name) do
    send_command(node_name, "Aecore.Chain.Worker.chain_state().naming")
  end

  # server

  def handle_call({:send_command, node_name, cmd}, _, state) do
    result = Port.command(state[node_name].process_port, cmd)
    {:reply, result, state}
  end

  def handle_call({:sync_two_nodes, node_name1, node_name2}, _, state) do
    port = state[node_name2].port
    cmd = "Aecore.Peers.Worker.add_peer(\"localhost:#{port}\")\n"
    result = Port.command(state[node_name1].process_port, cmd)
    {:reply, result, state}
  end

  def handle_call({:get_state}, _, state) do
    {:reply, state, state}
  end

  def handle_call({:alive_ports}, _, state) do
    alive_ports = for {name, _} <- state, do: Port.info(state[name].port)
    {:reply, alive_ports, state}
  end

  def handle_info({process_port, {:data, result}}, state) do
    if Regex.match?(~r/[%]Aecore.Chain.Block/, result) do
      node = Enum.find(state, fn {_, value} -> value.process_port == process_port end)
      state = put_in(state[elem(node, 0)].top_block, result)
    end

    IO.inspect(result)
    {:noreply, state}
  end

  def handle_call({:new_node, port}, _, state) do
    new_node_num = (Enum.count(state) + 1) |> to_string()
    name = "node" <> new_node_num
    {:ok, tmp_path} = Temp.mkdir(name)
    System.cmd("cp", ["-R", System.cwd(), tmp_path])
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
      Map.put(state, name, %{
        process_port: process_port,
        path: tmp_path,
        port: port,
        top_block: nil
      })

    {:reply, new_state, new_state}
  end
end
