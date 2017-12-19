defmodule Aehttpserver.Web.BalanceController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain

  def show(conn, params) do
      case(Base.decode16(params["account"])) do
        :error ->
          "can't be decoded"
        {:ok, acc} ->
          case(Chain.chain_state[acc]) do
            nil ->
              json conn, %{"balance" => 0, "account" => "unknown"}
            %{balance: balance} ->
              json conn, %{"balance" => balance, "account" => params["account"]}
          end
      end
  end
end
