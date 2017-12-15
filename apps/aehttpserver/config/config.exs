# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# General application configuration
config :aehttpserver,
  namespace: Aehttpserver

# Configures the endpoint
config :aehttpserver, Aehttpserver.Web.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "iC7edxvq+oLqfi0E3jpHq9hq0PLu+n0xeJkjxRwPO+klI8fR8s/5n+Y30asPxlYo",
  render_errors: [view: Aehttpserver.Web.ErrorView, accepts: ~w(html json)]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
