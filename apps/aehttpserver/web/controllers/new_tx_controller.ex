defmodule Aehttpserver.NewTxController do
  use Aehttpserver.Web, :controller

  alias Aecore.Structures.Block
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Utils.Serialization
  alias Aecore.Keys.Worker, as: Keys


  def new_tx(conn, _params) do
    ## Simplest way to convert all keys in map to atoms is to
    ## encode and decode it again.
    Poison.encode!(conn.body_params)
    |> Poison.decode!([keys: :atoms])
    |> Serialization.tx(:deserialize)
    |> Aecore.Txs.Pool.Worker.add_transaction()
    json conn, %{:status => :new_tx_added}
  end
end
