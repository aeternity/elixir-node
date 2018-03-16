# This file is responsible for configuring your application
# and its dependencies with the aid of the Mix.Config module.
use Mix.Config

# This configuration is loaded before any dependency and is restricted
# to this project. If another project depends on this project, this
# file won't be loaded nor affect the parent project. For this reason,
# if you want to provide default values for your application for
# 3rd-party users, it should be done in your "mix.exs" file.

# You can configure for your application as:
#
#     config :aecore, key: :value
#
# And access this configuration in your application as:
#
#     Application.get_env(:aecore, :key)
#
# Or configure a 3rd-party app:
#
#     config :logger, level: :info
#

# It is also possible to import configuration files, relative to this
# directory. For example, you can emulate configuration per environment
# by uncommenting the line below and defining dev.exs, test.exs and such.
# Configuration from the imported file will override the ones defined
# here (which is why it is important to import them last).
#
path = Path.absname("apps/aecore")
%{year: year, month: month, day: day} = DateTime.utc_now()
timestamp = "#{year}-#{month}-#{day}_"

persistence_path =
  case System.get_env("PERSISTENCE_PATH") do
    nil -> "apps/aecore/priv/rox_db/"
    env -> env
  end

aewallet_pass =
  case System.get_env("AEWALLET_PASS") do
    nil -> " "
    env -> env
  end

aewallet_path =
  case System.get_env("AEWALLET_PATH") do
    nil -> "apps/aecore/priv/aewallet"
    env -> env
  end

config :aecore, :aewallet, pass: aewallet_pass

config :aecore, :aewallet, path: Path.absname(aewallet_path)

config :aecore, :persistence,
  path: persistence_path |> Path.absname() |> Path.join("//"),
  number_of_blocks_in_memory: 100

config :logger,
  compile_time_purge_level: :info,
  backends: [:console, {LoggerFileBackend, :info}, {LoggerFileBackend, :error}]

config :logger, :console, level: :error

config :logger, :info,
  path: path <> "/logs/#{timestamp}info.log",
  level: :info

config :logger, :error,
  path: path <> "/logs/#{timestamp}error.log",
  level: :error

import_config "#{Mix.env()}.exs"
