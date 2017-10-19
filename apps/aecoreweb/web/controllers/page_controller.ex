defmodule Aecoreweb.PageController do
  use Aecoreweb.Web, :controller

  def index(conn, _params) do
    render conn, "index.html"
  end
end
