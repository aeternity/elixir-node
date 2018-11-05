use Mix.Config

config :aehttpserver, Aehttpserver.Web.Endpoint,
  debug_errors: true,
  check_origin: false,
  watchers: []

# Do not include metadata nor timestamps in development logs
config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
