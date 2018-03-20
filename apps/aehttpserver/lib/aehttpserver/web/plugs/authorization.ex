defmodule Aehttpserver.Plugs.Authorization do
  @moduledoc """
  A plug which checks if the request authorization UUID matches the one from the server
  """

  import Plug.Conn

  def init(default), do: default

  def call(conn, _default) do
    env_authorization = Application.get_env(:aecore, :authorization)
    header_authorization = conn |> get_req_header("authorization") |> Enum.at(0)

    if env_authorization == header_authorization do
      conn
    else
      conn |> send_resp(401, "Unauthorized") |> halt()
    end
  end
end
