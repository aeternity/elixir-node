defmodule Aehttpserver.PingController do
  use Aehttpserver.Web, :controller

  def index(conn, _params) do
    json conn, %{response: "pong"}
  end
end
