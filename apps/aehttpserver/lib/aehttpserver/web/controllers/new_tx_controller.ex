defmodule Aehttpserver.Web.NewTxController do
  use Aehttpserver.Web, :controller

  alias Aeutil.Serialization
  alias Aeutil.HTTPUtil
  alias Aecore.Txs.Pool.Worker, as: Pool

  def new_tx(conn, _params) do
    deserialized_tx = Serialization.tx(conn.body_params, :deserialize)

    case Pool.add_transaction(deserialized_tx) do
      :error ->
        HTTPUtil.json_bad_request(conn, "Invalid transaction")

      :ok ->
        json(conn, "Successful operation")
    end
  end
end
