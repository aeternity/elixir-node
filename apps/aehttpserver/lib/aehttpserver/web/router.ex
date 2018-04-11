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
    # epoch gossip API
    get("/top", HeaderController, :top)
    get("/header-by-hash", HeaderController, :header_by_hash)
    get("/header-by-height", HeaderController, :header_by_height)
    get("/block-by-height", BlockController, :block_by_height)
    get("/block-by-hash", BlockController, :block_by_hash)
    post("/block", BlockController, :post_block)
    post("/tx", NewTxController, :post_tx)
    get("/peer/key", InfoController, :public_key)

    get("/info", InfoController, :info)
    get("/peers", PeersController, :info)
    resources("/tx", TxController, param: "account", only: [:show])
    get("/blocks", BlockController, :get_blocks)
    get("/raw_blocks", BlockController, :get_raw_blocks)
    get("/registered_oracles", OracleController, :registered_oracles)
    get("/pool_txs", TxPoolController, :get_pool_txs)
    resources("/balance", BalanceController, param: "account", only: [:show])
    resources("/tx_pool", TxPoolController, param: "account", only: [:show])
  end

  scope "/node", Aehttpserver.Web do
    pipe_through(:api)
    pipe_through(:authorized)

    post("/oracle_query", OracleController, :oracle_query)
    options("/oracle_query", OracleController, :options)

    post("/oracle_response", OracleController, :oracle_response)
    resources("/miner", MinerController, param: "operation", only: [:show])
  end
end
