defmodule Aehttpserver.Web.Endpoint do
  use Phoenix.Endpoint, otp_app: :aehttpserver

  alias Aeutil.Environment

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
  def init(_key, config) do
    if config[:load_from_system_env] do
      port = String.to_integer(Environment.get_env_or_default("PORT", "4000"))
      {:ok, Keyword.put(config, :http, [:inet6, port: port])}
    else
      {:ok, config}
    end
  end
end
