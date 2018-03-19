defmodule Aehttpserver.Web.NewTxController do
  use Aehttpserver.Web, :controller

  alias Aeutil.Serialization
  alias Aecore.Txs.Pool.Worker, as: Pool

  def new_tx(conn, _params) do
    conn.body_params
    |> Serialization.tx(:deserialize)
    |> Pool.add_transaction()

    json(conn, %{:status => :new_tx_added})
  end
end
