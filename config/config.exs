# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# By default, the umbrella project as well as each child
# application will require this configuration file, ensuring
# they all use the same configuration. While one could
# configure all applications here, we prefer to delegate
# back to each application for organization purposes.
import_config "../apps/*/config/config.exs"

%{year: year, month: month, day: day} = DateTime.utc_now()
timestamp = "[#{year}-#{month}-#{day}]"

config :aecore, :keys,
  password: "secret",
  dir: "/tmp/keys"

config :logger,
  compile_time_purge_level: :info,
  backends: [{LoggerFileBackend, :miner_info},
             {LoggerFileBackend, :chain_info}]

config :logger, :miner_info,
  path: "apps/aecore/logs/#{timestamp}miner_info.log",
  level: :info,
  metadata_filter: [miner: :info]


config :logger, :chain_info,
  path: "apps/aecore/logs/#{timestamp}chain_info.log",
  level: :info,
  metadata_filter: [chain: :info]
