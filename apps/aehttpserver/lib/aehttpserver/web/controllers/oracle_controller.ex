defmodule Aehttpserver.Web.OracleController do
  use Aehttpserver.Web, :controller

  alias Aecore.Oracle.Oracle
  alias Aecore.Account.Account
  alias Aecore.Tx.SignedTx

  require Logger

  def oracle_response(conn, _params) do
    %{
      data: %{
        payload: %{
          query_id: query_id
        },
        fee: fee
      }
    } = SignedTx.deserialize(conn.body_params)

    case Oracle.respond(
           query_id,
           query_id,
           fee
         ) do
      :ok ->
        json(conn, %{:status => :ok})

      :error ->
        json(conn, %{:status => :error})
    end
  end

  def registered_oracles(conn, _params) do
    registered_oracles = Oracle.get_registered_oracles()

    serialized_oracle_list =
      if Enum.empty?(registered_oracles) do
        %{}
      else
        Enum.reduce(registered_oracles, %{}, fn {address,
                                                 %{owner: owner} = registered_oracle_state},
                                                acc ->
          Map.put(
            acc,
            Account.base58c_encode(address),
            Map.put(registered_oracle_state, :owner, Account.base58c_encode(owner.value))
          )
        end)
      end

    json(conn, serialized_oracle_list)
  end

  def oracle_query(conn, _params) do
    %{
      data: %{
        fee: fee,
        payload: %{
          oracle_address: %{
            value: value
          },
          query_data: query_data,
          query_fee: query_fee,
          query_ttl: query_ttl,
          response_ttle: response_ttl
        }
      }
    } = SignedTx.deserialize(conn.body_params)

    case Oracle.query(
           value,
           query_data,
           query_fee,
           fee,
           query_ttl,
           response_ttl
         ) do
      :ok ->
        json(conn, %{:status => :ok})

      :error ->
        json(conn, %{:status => :error})
    end
  end
end
