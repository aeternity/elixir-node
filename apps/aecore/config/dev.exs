use Mix.Config

persistence_path =
  case System.get_env("PERSISTENCE_PATH") do
    nil -> "/rox_db/"
    env -> env
  end

config :aecore, :persistence,
  path: Path.absname(persistence_path),
  write_options: [sync: true, disable_wal: false]

accounts_path =
  case System.get_env("ACCOUNTS_PATH") do
    nil -> "/genesis/"
    env -> env
  end

config :aecore, :account_path, path: Path.absname(accounts_path)

new_candidate_nonce_count =
  case System.get_env("NEW_CANDIDATE_NONCE_COUNT") do
    nil -> 10
    env -> env
  end

config :aecore, :pow,
  new_candidate_nonce_count: new_candidate_nonce_count,
  bin_dir: "/cuckoo/bin",
  params: {"./lean16", "-t 5", 16},
  max_target_change: 1

sync_port =
  case System.get_env("SYNC_PORT") do
    nil -> 3015
    env -> String.to_integer(env)
  end

config :aecore, :peers,
  ranch_acceptors: 10,
  sync_port: sync_port

config :aecore, :miner, resumed_by_default: false

config :aecore, :pow_module, Aecore.Pow.Cuckoo
