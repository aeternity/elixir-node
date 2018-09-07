use Mix.Config

port =
  case System.get_env("PORT") do
    nil -> 4000
    env -> env
  end

config :aehttpserver, Aehttpserver.Web.Endpoint,
  http: [port: port],
  debug_errors: true,
  check_origin: false,
  watchers: []

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
