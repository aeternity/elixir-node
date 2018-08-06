use Mix.Config

config :aehttpserver, namespace: Aehttpserver

config :aehttpserver, Aehttpserver.Web.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "iC7edxvq+oLqfi0E3jpHq9hq0PLu+n0xeJkjxRwPO+klI8fR8s/5n+Y30asPxlYo",
  render_errors: [view: Aehttpserver.Web.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Aehttpserver.PubSub, adapter: Phoenix.PubSub.PG2]

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

import_config "#{Mix.env()}.exs"
