use Mix.Config

config :aehttpserver, Aehttpserver.Web.Endpoint,
  on_init: {Aehttpserver.Web.Endpoint, :load_from_system_env, []},
  url: [host: "localhost", port: 4000]

config :logger, level: :info

import_config "prod.secret.exs"
