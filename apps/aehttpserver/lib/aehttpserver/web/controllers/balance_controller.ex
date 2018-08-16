defmodule Aehttpserver.Web.BalanceController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.Account

  def show(conn, params) do
    acc = Account.base58c_decode(params["account"])
    tree = Chain.chain_state().accounts

    balance = Account.balance(tree, acc)
    json(conn, %{"balance" => balance, "account" => params["account"]})
  end
end
