defmodule Aehttpserver.Web.NewTxController do
  use Aehttpserver.Web, :controller

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Structures.SignedTx

  def new_tx(conn, _params) do
    conn.body_params
    |> SignedTx.deserialize()
    |> Pool.add_transaction()

    json(conn, %{:status => :new_tx_added})
  end
end
