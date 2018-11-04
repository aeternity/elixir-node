use Mix.Config

config :aehttpserver, Aehttpserver.Web.Endpoint, url: [host: "localhost"]

config :logger, level: :info

import_config "prod.secret.exs"
