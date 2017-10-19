defmodule Aecoreweb.PingController do
  use Aecoreweb.Web, :controller

  def index(conn, _params) do
    json conn, %{response: "pong"}
  end
end
