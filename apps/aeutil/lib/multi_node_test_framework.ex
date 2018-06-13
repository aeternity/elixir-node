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

  def mine_sync_block(node_name) do
    GenServer.call(__MODULE__, {:mine_sync_block, node_name})
  end

  def sync_two_nodes(node_name1, node_name2) do
    GenServer.call(__MODULE__, {:sync_two_nodes, node_name1, node_name2})
  end

  def alive_ports() do
    GenServer.call(__MODULE__, {:alive_ports})
  end

  def get_node_top_block(node_name) do
    GenServer.call(__MODULE__, {:get_node_top_block, node_name})
  end

  def handle_call({:mine_sync_block, node_name}, _, state) do
    cmd = "Aecore.Miner.Worker.mine_sync_block_to_chain()\n"
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

  def handle_call({:get_node_top_block, node_name}, _, state) do
    cmd = "Aecore.Chain.Worker.top_block()\n"
    result = Port.command(state[node_name].process_port, cmd)
    {:reply, result, state}
  end

  def handle_call({:alive_ports}, _, state) do
    alive_ports = for {name, _} <- state, do: Port.info(state[name].port)
    {:reply, alive_ports, state}
  end

  def handle_info({port, {:data, result}}, state) do
    IO.inspect result
    {:noreply, state}
  end

  def handle_call({:new_node, port}, _, state) do
    new_node_num = Enum.count(state) + 1 |> to_string()
    name = "node" <> new_node_num
    {:ok, tmp_path} = Temp.mkdir name
    System.cmd("cp", ["-R", System.cwd, tmp_path])
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
    new_state = Map.put(state, name, %{process_port: process_port, path: tmp_path, port: port, top_block: nil})
    {:reply, new_state, new_state}
  end
end
