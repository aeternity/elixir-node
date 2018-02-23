defmodule Aehttpserver.Web.OracleController do
  use Aehttpserver.Web, :controller

  alias Aecore.OraclePrototype.Oracle
  alias Aeutil.Bits

  require Logger

  def oracle_response(conn, _params) do
    body = conn.body_params
    binary_oracle_hash = Bits.bech32_decode(body["oracle_hash"])
    case Oracle.respond(binary_oracle_hash, body["response"], body["fee"]) do
      :ok ->
        json conn, %{:status => :ok}
      :error ->
        json conn, %{:status => :error}
    end
  end
end
