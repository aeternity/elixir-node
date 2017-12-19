defmodule Aehttpserver.Plugs.SetHeader do
  import Plug.Conn

  def init(default), do: default

  def call(conn, _default) do
    put_resp_header(conn, "server", "aehttpserver")
  end

end
