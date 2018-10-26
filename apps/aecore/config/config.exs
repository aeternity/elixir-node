use Mix.Config

%{year: year, month: month, day: day} = DateTime.utc_now()
time = "#{year}-#{month}-#{day}_"

persistence_path =
  case System.get_env("PERSISTENCE_PATH") do
    nil -> "/rox_db/"
    env -> env
  end

sign_keys_pass =
  case System.get_env("SIGN_KEYS_PASS") do
    nil -> <<"secret">>
    env -> env
  end

sign_keys_path =
  case System.get_env("SIGN_KEYS_PATH") do
    nil -> "/signkeys"
    env -> env
  end

peer_keys_pass =
  case System.get_env("PEER_KEYS_PASS") do
    nil -> <<"secret">>
    env -> env
  end

peerkeys_path =
  case System.get_env("PEER_KEYS_PATH") do
    nil -> "/peerkeys"
    env -> env
  end

accounts_path =
  case System.get_env("ACCOUNTS_PATH") do
    nil -> "/genesis/"
    env -> env
  end

config :aecore, :spend_tx, version: 1

config :aecore, :sign_keys, pubkey_size: 32

config :aecore, :signed_tx, sign_max_size: 72

config :aecore, :oracle_response_tx, query_id: 64

config :aecore, :peer_keys, path: Path.absname(peerkeys_path)

config :aecore, :naming,
  max_label_length: 63,
  max_name_length: 253

config :aecore, :sign_keys,
  pass: sign_keys_pass,
  path: Path.absname(sign_keys_path)

config :aecore, :peer_keys,
  pass: peer_keys_pass,
  path: Path.absname(peerkeys_path)

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
  path: "/logs/#{time}info.log",
  level: :info

config :logger, :error,
  path: "/logs/#{time}error.log",
  level: :error

import_config "#{Mix.env()}.exs"
