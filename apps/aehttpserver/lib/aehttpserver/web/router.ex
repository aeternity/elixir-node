defmodule Aehttpserver.Web.Router do
  use Aehttpserver.Web, :router

  pipeline :api do
    plug(CORSPlug, origin: "*")
    plug(:accepts, ["json"])
    plug(Aehttpserver.Plugs.SetHeader)
  end

  pipeline :authorized do
    plug(Aehttpserver.Plugs.Authorization)
  end

  scope "/", Aehttpserver.Web do
    pipe_through(:api)

    get("/info", InfoController, :info)
    post("/new_tx", NewTxController, :new_tx)
    get("/peers", PeersController, :info)
    resources("/tx", TxController, param: "account", only: [:show])
    post("/new_block", BlockController, :new_block)
    post("/oracle_query", OracleController, :oracle_query)
    options("/oracle_query", OracleController, :options)
    get("/blocks", BlockController, :get_blocks)
    get("/raw_blocks", BlockController, :get_raw_blocks)
    get("/registered_oracles", OracleController, :registered_oracles)
    get("/pool_txs", TxPoolController, :get_pool_txs)
    resources("/block", BlockController, param: "hash", only: [:show])
    resources("/balance", BalanceController, param: "account", only: [:show])
    resources("/tx_pool", TxPoolController, param: "account", only: [:show])
  end

  scope "/node", Aehttpserver.Web do
    pipe_through(:api)
    pipe_through(:authorized)

    post("/oracle_response", OracleController, :oracle_response)
    resources("/miner", MinerController, param: "operation", only: [:show])
  end
end
