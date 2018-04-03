defmodule Aehttpserver.Web.OracleController do
  use Aehttpserver.Web, :controller

  alias Aecore.Oracle.Oracle
  alias Aecore.Structures.Account
  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Serialization
  alias Aeutil.Bits

  require Logger

  def oracle_response(conn, _params) do
    body = conn.body_params
    binary_query_id = Bits.decode58(body["query_id"])

    case Oracle.respond(binary_query_id, body["response"], body["fee"]) do
      :ok ->
        json(conn, %{:status => :ok})

      :error ->
        json(conn, %{:status => :error})
    end
  end

  def registered_oracles(conn, _params) do
    registered_oracles = Chain.registered_oracles()

    serialized_oracle_list =
      if Enum.empty?(registered_oracles) do
        %{}
      else
        Enum.reduce(Chain.registered_oracles(), %{}, fn {address, %{tx: tx}}, acc ->
          Map.put(
            acc,
            Account.base58c_encode(address),
            Serialization.tx(tx, :serialize)
          )
        end)
      end

    json(conn, serialized_oracle_list)
  end

  def oracle_query(conn, _params) do
    body = conn.body_params
    binary_oracle_address = Bits.decode58(body["address"])
    parsed_query = Poison.decode!(~s(#{body["query"]}))

    case Oracle.query(
           binary_oracle_address,
           parsed_query,
           body["query_fee"],
           body["fee"],
           body["query_ttl"],
           body["response_ttl"]
         ) do
      :ok ->
        json(conn, %{:status => :ok})

      :error ->
        json(conn, %{:status => :error})
    end
  end
end
