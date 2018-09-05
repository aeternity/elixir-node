defmodule Aehttpserver.Web.TxController do
  use Aehttpserver.Web, :controller

  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aeutil.Serialization
  alias Aecore.Account.Account

  def show(conn, params) do
    account_bin = Account.base58c_decode(params["account"])
    user_txs = Pool.get_txs_for_address(account_bin)

    case user_txs do
      [] ->
        json(conn, [])

      _ ->
        json_info = Serialization.serialize_txs_info_to_json(user_txs)
        json(conn, json_info)
    end
  end
end
