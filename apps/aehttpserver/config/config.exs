# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.
use Mix.Config

# Configures the endpoint
config :aehttpserver, Aehttpserver.Endpoint,
  url: [host: "localhost"],
  secret_key_base: "5OCr9Ljxr0s8cSx36fmjKgi6hWETJeoxH+jMvBSNDCO/pt0Zqo1S0+EGGJ2VyOoa",
  render_errors: [view: Aehttpserver.ErrorView, accepts: ~w(html json)],
  pubsub: [name: Aehttpserver.PubSub,
           adapter: Phoenix.PubSub.PG2]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{Mix.env}.exs"
