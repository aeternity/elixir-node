use Mix.Config

path = Path.absname("apps/aecore")
%{year: year, month: month, day: day} = DateTime.utc_now()
time = "#{year}-#{month}-#{day}_"

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

peerkeys_path =
  case System.get_env("PEER_KEYS_PATH") do
    nil -> "apps/aecore/priv/peerkeys"
    env -> env
  end

accounts_path =
  case System.get_env("ACCOUNTS_PATH") do
    nil -> "apps/aecore/config/genesis/"
    env -> env
  end

config :aecore, :spend_tx, version: 1

config :aecore, :aewallet, pub_key_size: 32

config :aecore, :signed_tx, sign_max_size: 72

config :aecore, :oracle_response_tx, query_id: 65

config :aecore, :peer_keys, path: Path.absname(peerkeys_path)

config :aecore, :naming,
  max_label_length: 63,
  max_name_length: 253

config :aecore, :aewallet,
  pass: aewallet_pass,
  path: Path.absname(aewallet_path)

config :aecore, :peer_keys, path: Path.absname(peerkeys_path)

config :aecore, :account_path, path: Path.absname(accounts_path)

config :aecore, :persistence,
  path: persistence_path |> Path.absname() |> Path.join("//"),
  number_of_blocks_in_memory: 100,
  write_options: [sync: true, disable_wal: false]

config :logger,
  compile_time_purge_level: :info,
  backends: [:console, {LoggerFileBackend, :info}, {LoggerFileBackend, :error}]

config :logger, :console, level: :error

config :logger, :info,
  path: path <> "/logs/#{time}info.log",
  level: :info

config :logger, :error,
  path: path <> "/logs/#{time}error.log",
  level: :error

import_config "#{Mix.env()}.exs"
