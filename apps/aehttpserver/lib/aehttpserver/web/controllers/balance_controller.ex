defmodule Aehttpserver.Web.BalanceController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Bits

  def show(conn, params) do
    case Bits.decode58c(params["account"]) do
      {:error, reason} ->
        reason

      {prefix, acc} ->
        case Chain.chain_state()[acc] do
          nil ->
            json(conn, %{"balance" => 0, "account" => "unknown"})

          %{balance: balance} ->
            json(conn, %{"balance" => balance, "account" => params["account"]})
        end
    end
  end
end
