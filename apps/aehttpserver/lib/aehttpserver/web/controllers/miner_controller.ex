defmodule Aehttpserver.Web.MinerController do
  use Aehttpserver.Web, :controller

  alias Aecore.Miner.Worker, as: Miner

  def show(conn, params) do
    case params["operation"] do
      "start" ->
        json(conn, Miner.resume())

      "stop" ->
        json(conn, Miner.suspend())

      "status" ->
        state = Miner.get_state()
        json(conn, state)
    end
  end
end
