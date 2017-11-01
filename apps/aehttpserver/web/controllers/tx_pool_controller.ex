defmodule Aehttpserver.TxPoolController do
  use Aehttpserver.Web, :controller

  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Utils.Serialization

  def show(conn, params) do
    pool_txs = Map.values(Pool.get_pool)
    case(Base.decode16(params["account"])) do
      :error ->
        "can't be decoded"
      {:ok, acc} ->
        acc_txs = get_acc_txs(pool_txs, acc)
        json(conn,
          Enum.map(acc_txs, fn(tx) -> Serialization.tx(tx, :serialize) end))
    end
  end

  def get_acc_txs(pool_txs, acc) do
    Enum.filter(pool_txs, fn(tx) ->
        tx.data.from_acc == acc || tx.data.to_acc == acc
      end)
  end
end
