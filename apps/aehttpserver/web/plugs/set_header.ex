defmodule Aehttpserver.Plugs.SetHeader do
  import Plug.Conn

  # def on_response(status, headers, _body, request) do
  #   {status, List.keyreplace(headers, "server", 0, {"server", "aehttpserver"}), request}
  # end

  def init(default), do: default

  def call(conn, _default) do
    put_resp_header(conn, "server", "aehttpserver")
  end

end
