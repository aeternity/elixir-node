defmodule Aehttpserver.PageController do
  use Aehttpserver.Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
