defmodule Aehttpserver.Web.NewTxController do
  use Aehttpserver.Web, :controller

  alias Aeutil.Serialization
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Structures.MultisigTx
  alias Aecore.Structures.SignedTx


  def new_tx(conn, _params) do
    # Simplest way to convert all keys in map to atoms is to
    # encode and decode it again.
    tx = conn.body_params
    case tx do
      %MultisigTx{} ->
        tx
      %SignedTx{} ->
        tx |> Poison.encode!() |> Poison.decode!([keys: :atoms])
    end
    |> Serialization.tx(:deserialize)
    |> Pool.add_transaction()

    json conn, %{:status => :new_tx_added}
  end
end
