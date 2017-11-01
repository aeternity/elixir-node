defmodule Aehttpserver.NewTxController do
  use Aehttpserver.Web, :controller

  alias Aecore.Utils.Serialization
  alias Aecore.Txs.Pool.Worker, as: Pool

  def new_tx(conn, _params) do
    conn.body_params["_json"]
    |> Poison.decode!([keys: :atoms])
    |> Serialization.tx(:deserialize)
    |> Pool.add_transaction()
    json conn, %{:status => :new_tx_added}
  end
end
