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

  def alive_ports() do
    GenServer.call(__MODULE__, {:alive_ports})
  end

  def get_node_chainstate(node_name) do
    GenServer.call(__MODULE__, {:get_node_chainstate, node_name})
  end

  def command(node_name, command) do
    GenServer.call(__MODULE__, {:command, node_name, command})
  end

  def run_nodes_test() do
    GenServer.call(__MODULE__, {:run_nodes_test})
  end

  def handle_call({:get_state}, _, state) do
    {:reply, state, state}
  end

  def handle_call({:get_node_chainstate, node_name}, _, state) do
    result = Port.command(state[node_name].port, "Aecore.Chain.Worker.top_block()")
    {:reply, result, state}
  end

  def handle_call({:alive_ports}, _, state) do
    alive_ports = for {name, info} <- state, do: Port.info(state[name].port)
    {:reply, alive_ports, state}
  end

  def handle_call({:command, node_name, command}, _, state) do
    result = Port.command(state[node_name].port, command)
    {:reply, result, state}
  end

  def handle_info({port, {:data, result}}, state) do
    IO.puts "Elixir got: #{inspect result}"
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

    port = Port.open({:spawn, "iex -S mix phx.server"}, [:binary, cd: tmp_path])
    new_state = Map.put(state, name, %{port: port, path: tmp_path})
    {:reply, new_state, new_state}
  end
end
