defmodule Aehttpserver.Router do
  use Aehttpserver.Web, :router

  pipeline :api do
    plug CORSPlug, [origin: "*"]
    plug :accepts, ["json"]
  end

  pipeline :authorized do
    plug :authorization
  end

  scope "/", Aehttpserver do
    pipe_through :api

    get "/info", InfoController, :info
    post "/new_tx", NewTxController, :new_tx
    get "/peers", PeersController, :info
    post "/new_block", BlockController, :new_block
    get "/blocks", BlockController, :get_blocks
    resources "/block", BlockController, param: "hash", only: [:show]
    resources "/balance", BalanceController, param: "account", only: [:show]
    resources "/tx_pool", TxPoolController, param: "account", only: [:show]
  end

  scope "/node", Aehttpserver do
    pipe_through :api
    pipe_through :authorized

    resources "/miner", MinerController, param: "operation", only: [:show]
  end

  def authorization(conn, _opts) do
    uuid = Application.get_env(:aecore, :authorization)
    header_uuid = Plug.Conn.get_req_header(conn, "authorization") |> Enum.at(0)

    if uuid == header_uuid do
      conn
    else
      conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end

end
