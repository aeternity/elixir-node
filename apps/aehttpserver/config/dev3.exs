use Mix.Config

config :aehttpserver, Aehttpserver.Web.Endpoint,
  http: [port: 4003],
  debug_errors: true,
  check_origin: false,
  server: true,
  watchers: []

config :logger, :console, format: "[$level] $message\n"

config :phoenix, :stacktrace_depth, 20
