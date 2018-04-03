defmodule Aehttpserver.Web.BalanceController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.Account

  def show(conn, params) do
    acc = Account.base58c_decode(params["account"])

    case Chain.chain_state()[acc] do
      nil ->
        json(conn, %{"balance" => 0, "account" => "unknown"})

      %{balance: balance} ->
        json(conn, %{"balance" => balance, "account" => params["account"]})
    end
  end
end
