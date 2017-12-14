use Mix.Config

%{year: year, month: month, day: day} = DateTime.utc_now()
timestamp = "#{year}-#{month}-#{day}_"

config :aecore, :persistence,
  path: Path.absname("_build/dev1/priv/rox_db")

config :logger,
  compile_time_purge_level: :info,
  backends: [:console,
             {LoggerFileBackend, :info},
             {LoggerFileBackend, :error}]

config :logger, :info,
  path: Path.absname("_build/dev1/logs/#{timestamp}info.log"),
  level: :info

config :logger, :error,
  path: Path.absname("_build/dev1/logs/#{timestamp}error.log"),
  level: :error

config :aecore, :peers,
  peers_target_count: 3,
  peers_max_count: 4
