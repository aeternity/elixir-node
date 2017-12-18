defmodule Aehttpserver.Web.NewTxController do
  use Aehttpserver.Web, :controller

  alias Aeutil.Serialization
  alias Aecore.Txs.Pool.Worker, as: Pool


  def new_tx(conn, _params) do
    ## Simplest way to convert all keys in map to atoms is to
    ## encode and decode it again.
    Poison.encode!(conn.body_params)
    |> Poison.decode!([keys: :atoms])
    |> Serialization.tx(:deserialize)
    |> Pool.add_transaction()
    json conn, %{:status => :new_tx_added}
  end
end
