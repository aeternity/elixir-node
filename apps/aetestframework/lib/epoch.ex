defmodule Aetestframework.Epoch do

  alias Aetestframework.Worker, as: TestFramework
  use Agent
  require Logger

  def start_link(_args) do
    Agent.start_link(fn -> %{} end, name: __MODULE__)
  end

  def start_epoch(path) do
    run_build(path)
    port = open_port(path)

    Agent.update(__MODULE__, fn _ ->
      %{
        process_port: port,
        path: path
      }
    end)
  end

  def stop_epoch do
    port = get_process_port()
    Port.command(port, "halt().\n")
    Port.close(port)
    Agent.update(__MODULE__, fn _ -> %{} end)
  end

  def get_state() do
    Agent.get(__MODULE__, fn state -> state end)
  end

  def get_process_port() do
    Agent.get(__MODULE__, fn state -> state.process_port end)
  end

  def download_epoch_release do
    path = String.replace(System.cwd(), ~r/(elixir-node).*$/, "")
    System.cmd("git", ["clone", "https://github.com/aeternity/epoch.git"], cd: path)
    System.cmd("git", ["checkout", "v0.16.0"], cd: path <> "epoch")
    path <> "epoch"
  end

  def run_build(path) do
    System.cmd("make", ["dev1-build"], cd: path)
    System.cmd("make", ["dev1-start"], cd: path)
    receive_result()
  end

  def open_port(path) do
    Port.open({:spawn, "make dev1-attach"}, [:binary, cd: path])
  end

  def get_peer_pubkey() do
    process_port = get_process_port()
    Port.command(process_port, "{ok, Pubkey} = aec_keys:peer_pubkey().\n")
    Port.command(process_port, "{\"pubkey_response\", base64:encode(Pubkey)}.\n")
    receive_result()
  end

  def get_top_block_hash() do
    Port.command(get_process_port(), "{\"hash_response\", base64:encode(aec_chain:top_block_hash())}.\n")
    hash = receive_result()
    Base.decode64!(hash)
  end

  def compare_hash(node) do
    TestFramework.update_node_top_block_hash(node)
    elixir_node_hash = TestFramework.get_top_block_hash(node)
    epoch_hash = get_top_block_hash()

    case {elixir_node_hash, epoch_hash} do
      {hash, hash} when hash != nil ->
        :synced
      _ ->
        :not_synced
    end
  end

  def receive_result do
    receive do
      {_, {:data, result}} ->
        IO.inspect result
        cond do
          res = Regex.run(~r/<<(.*)>>/, result) ->
            res
            |> List.last
            |> String.replace("\"", "")

          result =~ "error" ->
            Logger.error(fn -> result end)

          true ->
            receive_result()
        end
    after
      2000 ->
        :ok
    end
  end

  def sync_with_elixir(node) do
    pubkey = get_peer_pubkey()
    TestFramework.send_command(node, "pubkey = Base.decode64!(\"#{pubkey}\")")
    cmd = "Peers.try_connect(%{host: 'localhost', port: 3015, pubkey: pubkey})"
    TestFramework.send_command(node, cmd)
  end
end
