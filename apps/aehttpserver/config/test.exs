use Mix.Config

config :aehttpserver, Aehttpserver.Web.Endpoint,
  http: [port: 4004],
  server: true

# Print only warnings and errors during test
config :logger, level: :warn
