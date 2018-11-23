use Mix.Config

%{year: year, month: month, day: day} = DateTime.utc_now()
time = "#{year}-#{month}-#{day}_"

config :aecore, :spend_tx, version: 1

config :aecore, :sign_keys, pubkey_size: 32

config :aecore, :signed_tx, sign_max_size: 72

config :aecore, :oracle_response_tx, query_id: 64

config :aecore, :naming,
  max_label_length: 63,
  max_name_length: 253

config :aecore, :persistence,
  number_of_blocks_in_memory: 100,
  write_options: [sync: true, disable_wal: false]

config :logger,
  compile_time_purge_level: :info,
  backends: [:console, {LoggerFileBackend, :info}, {LoggerFileBackend, :error}]

config :logger, :console, level: :error

config :logger, :info,
  path: "logs/#{time}info.log",
  level: :info

config :logger, :error,
  path: "logs/#{time}error.log",
  level: :error

import_config "#{Mix.env()}.exs"
