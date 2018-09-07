use Mix.Config

port =
  case System.get_env("PORT") do
    nil -> 4000
    env -> env
  end

config :aehttpserver, Aehttpserver.Web.Endpoint,
  http: [port: port],
  server: true

# Print only warnings and errors during test
config :logger, level: :warn
