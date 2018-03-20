defmodule Aehttpserver.Plugs.SetHeader do
  @moduledoc """
  A plug that adds a header which confirms that the server is an aehttpserver to every response
  """

  import Plug.Conn

  def init(default), do: default

  def call(conn, _default) do
    put_resp_header(conn, "server", "aehttpserver")
  end

end
