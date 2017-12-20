defmodule Aehttpserver.Web.OracleController do
  use Aehttpserver.Web, :controller

  alias Aecore.OraclePrototype.Oracle

  def oracle_response(conn, _params) do
    body = conn.body_params
    binary_oracle_hash = Base.decode16!(body["oracle_hash"])
    IO.inspect(binary_oracle_hash)
    IO.inspect(body["response"])
    IO.inspect(body["fee"])
    case Oracle.respond(binary_oracle_hash, body["response"], body["fee"]) do
      :ok ->
        json conn, %{:status => :ok}
      :error ->
        json conn, %{:status => :error}
    end
  end
end
