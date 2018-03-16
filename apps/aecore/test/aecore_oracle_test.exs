defmodule AecoreOracleTest do
  use ExUnit.Case

  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Miner.Worker, as: Miner

  test "register and query an oracle, check response" do
    register_oracle()
    query_oracle()
    oracle_respond()

    interaction_object = Chain.oracle_interaction_objects() |> Map.values() |> Enum.at(0)

    assert nil != interaction_object.response
  end

  def register_oracle() do
    query_format = %{
      "type" => "object",
      "properties" => %{"currency" => %{"type" => "string"}}
    }

    response_format = %{
      "type" => "object",
      "properties" => %{
        "base" => %{"type" => "string"},
        "date" => %{"type" => "string"},
        "rates" => %{"type" => "object"}
      }
    }

    Oracle.register(
      query_format,
      response_format,
      "Gives the rates for a currency with EUR as base",
      10
    )

    Miner.mine_sync_block_to_chain()
    Miner.mine_sync_block_to_chain()
  end

  def query_oracle() do
    oracle_address = Chain.registered_oracles() |> Map.keys() |> Enum.at(0)
    Oracle.query(oracle_address, %{"currency" => "USD"}, 5, 10)
    Miner.mine_sync_block_to_chain()
  end

  def oracle_respond() do
    query_id = Chain.oracle_interaction_objects() |> Map.keys() |> Enum.at(0)
    Oracle.respond(query_id, %{"value" => 1}, 5)
    Miner.mine_sync_block_to_chain()
  end
end
