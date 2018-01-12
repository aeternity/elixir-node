defmodule Aehttpserver.Web.Router do
  use Aehttpserver.Web, :router

  pipeline :api do
    plug CORSPlug, [origin: "*"]
    plug :accepts, ["json"]
    plug Aehttpserver.Plugs.SetHeader
  end

  pipeline :authorized do
    plug Aehttpserver.Plugs.Authorization
  end

  scope "/", Aehttpserver.Web do
    pipe_through :api

    post "/new_tx", NewTxController, :new_tx
    post "/new_block", BlockController, :new_block
    post "/channel_invite", ChannelController, :invite
    post "/channel_accept", ChannelController, :accept
    get "/info", InfoController, :info
    get "/peers", PeersController, :info
    get "/blocks", BlockController, :get_blocks
    get "/pool_txs", TxPoolController, :get_pool_txs
    resources "/block", BlockController, param: "hash", only: [:show]
    resources "/balance", BalanceController, param: "account", only: [:show]
    resources "/tx_pool", TxPoolController, param: "account", only: [:show]
  end

  scope "/node", Aehttpserver.Web do
    pipe_through :api
    pipe_through :authorized

    resources "/miner", MinerController, param: "operation", only: [:show]
  end

end
