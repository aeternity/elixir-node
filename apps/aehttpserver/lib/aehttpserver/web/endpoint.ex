defmodule Aehttpserver.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :aehttpserver

  socket("/socket", Aehttpserver.Web.UserSocket)

  plug(Plug.Logger, log: :debug)

  plug(
    Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Poison
  )

  plug(Aehttpserver.Web.Router)

  @doc """
  Dynamically loads configuration from the system environment
  on startup.

  It receives the endpoint configuration from the config files
  and must return the updated configuration.
  """
  def load_from_system_env(config) do
    port = System.get_env("PORT") || raise "expected the PORT environment variable to be set"

    {:ok, Keyword.put(config, :http, [:inet6, port: port])}
  end
end
