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

    get "/info", InfoController, :info
    post "/new_tx", NewTxController, :new_tx
    get "/peers", PeersController, :info
    resources "/tx", TxController, param: "account", only: [:show]
    post "/new_block", BlockController, :new_block
    get "/blocks", BlockController, :get_blocks
    get "/raw_blocks", BlockController, :get_raw_blocks
    get "/pool_txs", TxPoolController, :get_pool_txs
    resources "/block", BlockController, param: "hash", only: [:show]
    resources "/balance", BalanceController, param: "account", only: [:show]
    resources "/tx_pool", TxPoolController, param: "account", only: [:show]
    post "/voting/new_voting/question", VotingController, :voting_request
    post "/voting/new_voting/answer", VotingController, :voting_request
    post "/voting/get_registered_questions", VotingController, :show_registered_questions
  end

  scope "/node", Aehttpserver.Web do
    pipe_through :api
    pipe_through :authorized

    resources "/miner", MinerController, param: "operation", only: [:show]
  end

end
