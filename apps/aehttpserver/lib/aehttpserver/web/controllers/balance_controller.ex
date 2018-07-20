defmodule Aehttpserver.Web.BalanceController do
  use Aehttpserver.Web, :controller

  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.Account

  def show(conn, params) do
    acc = Account.base58c_decode(params["account"])
    account_state_tree = Chain.chain_state().accounts
    %{balance: balance} = AccountStateTree.get(account_state_tree, acc)

    json(conn, %{"balance" => balance, "account" => params["account"]})
  end
end
