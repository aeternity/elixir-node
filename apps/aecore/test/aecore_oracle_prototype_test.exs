defmodule AecoreOraclePrototypeTest do
  use ExUnit.Case

  alias Aecore.OraclePrototype.Oracle
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner

  setup do
    path = Path.absname("oracle.py")
    Task.async(fn -> System.cmd("python", [path]) end)
    :ok
  end

  test "register and query an oracle, check response" do
    register_oracle()
    query_oracle()
    :timer.sleep(5000)
    Miner.mine_sync_block_to_chain()
    oracle_pid =
      System.cmd("lsof", ["-t", "-i:4001"])
      |> elem(0)
      |> String.replace("\n", "")
    System.cmd("kill", [oracle_pid])
    assert false == Enum.empty?(Chain.oracle_responses())
  end

  def register_oracle() do
    query_format =
      %{"type" =>
          "object",
        "properties" =>
          %{"currency" => %{"type" => "string"}}}
    response_format =
      %{"type" =>
          "object",
        "properties" =>
          %{"base" => %{"type" => "string"},
            "date" => %{"type" => "string"},
            "rates" => %{"type" => "object"}}}
    Oracle.register(query_format, response_format,
      "Gives the rates for a currency with EUR as base", 10, "localhost:4001")
    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()
  end

  def query_oracle() do
    oracle_hash = Chain.registered_oracles |> Map.keys |> Enum.at(0)
    Oracle.query(oracle_hash, %{"currency" => "USD"}, 5, 10)
    Miner.mine_sync_block_to_chain()
  end
end
