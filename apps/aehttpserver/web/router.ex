defmodule Aehttpserver.Router do
  use Aehttpserver.Web, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_flash
    plug :put_secure_browser_headers
  end

  scope "/", Aehttpserver do
    pipe_through :browser # Use the default browser stack
    get "/info", InfoController, :info
    post "/new_tx", NewTxController, :new_tx
    get "/peers", PeersController, :info
    resources "/block", BlockController, param: "hash", only: [:show]
    resources "/balance", BalanceController, param: "account", only: [:show]
    resources "/tx_pool", TxPoolController, param: "account", only: [:show]
  end


  # Other scopes may use custom stacks.
  # scope "/api", Aehttpserver do
  #   pipe_through :api
  # end
end
