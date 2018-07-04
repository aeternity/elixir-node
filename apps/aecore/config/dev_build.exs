use Mix.Config

import_config "dev.exs"

%{year: year, month: month, day: day} = DateTime.utc_now()
time = "#{year}-#{month}-#{day}_"

config :aecore, :persistence, path: Path.absname("_build/dev_build/priv/rox_db")

config :aecore, :peer_keys, path: Path.absname("_build/dev_build/priv/peerkeys")

config :logger,
  compile_time_purge_level: :info,
  backends: [:console, {LoggerFileBackend, :info}, {LoggerFileBackend, :error}]

config :logger, :info,
  path: Path.absname("_build/dev_build/logs/#{time}info.log"),
  level: :info

config :logger, :error,
  path: Path.absname("_build/dev_build/logs/#{time}error.log"),
  level: :error

config :aecore, :miner, resumed_by_default: false
