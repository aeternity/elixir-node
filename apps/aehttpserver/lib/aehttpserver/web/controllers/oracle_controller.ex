defmodule Aehttpserver.Web.OracleController do
  use Aehttpserver.Web, :controller

  alias Aecore.OraclePrototype.Oracle

  require Logger

  def oracle_response(conn, _params) do
    body = conn.body_params
    binary_oracle_hash = Base.decode16(body["oracle_hash"])
    case binary_oracle_hash do
      {:ok, binary_hash} ->
        case Oracle.respond(binary_hash, body["response"], body["fee"]) do
          :ok ->
            json conn, %{:status => :ok}
          :error ->
            json conn, %{:status => :error}
        end
      :error ->
        Logger.error("Invalid hex input for oracle hash")
        json conn, %{:status => :error}
    end
  end
end
