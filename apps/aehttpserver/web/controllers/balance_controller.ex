defmodule Aehttpserver.BalanceController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain

  def show(conn, params) do
      case(Base.decode16(params["account"])) do
        :error ->
          "can't be decoded"
        {:ok, acc} ->
          case(Chain.chain_state[acc]) do
            nil ->
              json conn, %{"unknown" => 0}
            %{balance: balance} ->
              json conn, %{params["account"] => balance}
          end
      end
  end
end
