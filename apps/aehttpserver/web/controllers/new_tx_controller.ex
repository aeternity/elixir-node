defmodule Aehttpserver.NewTxController do
  use Aehttpserver.Web, :controller

  alias Aecore.Structures.Block
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Keys.Worker, as: Keys

  def new_tx(conn, _params) do
    #TODO: Move to serialization
    tx = Base.decode64!(conn.body_params["_json"])
    |> :erlang.binary_to_term
     Aecore.Txs.Pool.Worker.add_transaction(tx)
     json conn, %{:status => :new_tx_added}
  end
end
