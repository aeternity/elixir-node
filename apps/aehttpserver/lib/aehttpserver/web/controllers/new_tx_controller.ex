defmodule Aehttpserver.Web.NewTxController do
  use Aehttpserver.Web, :controller

  alias Aecore.Tx.SignedTx
  alias Aeutil.HTTPUtil
  alias Aecore.Tx.Pool.Worker, as: Pool

  def post_tx(conn, _params) do
    deserialized_tx = SignedTx.deserialize(conn.body_params)

    case Pool.add_transaction(deserialized_tx) do
      :error ->
        HTTPUtil.json_bad_request(conn, "Invalid transaction")

      :ok ->
        json(conn, "Successful operation")
    end
  end
end
