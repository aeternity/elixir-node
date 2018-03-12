use Mix.Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :aehttpserver, Aehttpserver.Web.Endpoint,
  http: [port: 4000],
  server: true

# Print only warnings and errors during test
config :logger, level: :warn
