defmodule Aehttpserver.MinerController do
  use Aehttpserver.Web, :controller

  alias Aecore.Miner.Worker, as: Miner

  def show(conn, params) do
    uuid = Application.get_env(:aecore, :authorization)
    header_uuid = Plug.Conn.get_req_header(conn, "uuid") |> Enum.at(0)
    if(uuid == header_uuid) do
      case(params["operation"]) do
        "start" ->
          json conn, Miner.resume()
        "stop" ->
          json conn, Miner.suspend()
        "status" ->
          {_, state} = Miner.get_state()
          json conn, state
      end
    else
      json conn, "uuid doesn't match"
    end
  end
end
