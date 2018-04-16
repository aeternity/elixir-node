defmodule Aehttpserver.Web.TxPoolController do
  use Aehttpserver.Web, :controller

  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aeutil.Serialization
  alias Aecore.Account.Account

  def show(conn, params) do
    pool_txs = Map.values(Pool.get_pool())
    acc = Account.base58c_decode(params["account"])

    acc_txs = get_acc_txs(pool_txs, acc)
    json(conn, Enum.map(acc_txs, fn tx -> Serialization.tx(tx, :serialize) end))
  end

  def get_pool_txs(conn, _params) do
    pool_txs =
      Pool.get_pool()
      |> Map.values()
      |> Enum.map(fn tx -> Serialization.tx(tx, :serialize) end)

    json(conn, pool_txs)
  end

  def get_acc_txs(pool_txs, acc) do
    Enum.filter(pool_txs, fn tx ->
      tx.data.sender == acc || tx.data.receiver == acc
    end)
  end
end
