use Mix.Config

import_config "dev.exs"

%{year: year, month: month, day: day} = DateTime.utc_now()
time = "#{year}-#{month}-#{day}_"

config :logger,
  compile_time_purge_level: :info,
  backends: [:console, {LoggerFileBackend, :info}, {LoggerFileBackend, :error}]

config :logger, :info, level: :info

config :logger, :error, level: :error

config :aecore, :miner, resumed_by_default: false
