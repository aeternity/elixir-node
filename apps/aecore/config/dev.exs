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

persistence_path = case System.get_env("PERSISTENCE_PATH") do
  nil -> "apps/aecore/priv/rox_db"
  env -> env
end

config :aecore, :persistence,
  path: Path.absname(persistence_path),
  write_options: [sync: true, disable_wal: false]

config :aecore, :pow,
  bin_dir: Path.absname("apps/aecore/priv/cuckoo/bin"),
  params: {"./lean", "-t 5", 16},
  max_difficulty_change: 1,
  genesis_header: %{
    height: 0,
    prev_hash: <<0::256>>,
    txs_hash: <<0::256>>,
    chain_state_hash: <<0 :: 256>>,
    timestamp: 1_507_275_094_308,
    nonce: 76,
    pow_evidence: [323333, 333635, 356466,
                   636139, 646165, 663665,
                   663739, 31306333, 31373934,
                   31376265, 31613030, 31633064,
                   31636339, 31653839, 32303738,
                   32306461, 32313830, 32323733,
                   32393364, 32396234, 33323435,
                   33346230, 33616139, 34323339,
                   34326132, 34326539, 34373434,
                   34643263, 35316335, 35363536,
                   35626131, 35653164, 36303962,
                   36323737, 36393163, 36666663,
                   37336636, 37356164, 37626237,
                   37633337, 37663630, 37666439],

    version: 1,
    difficulty_target: 1
  }

config :aecore, :peers,
  peers_target_count: 3,
  peers_max_count: 4

config :aecore, :miner,
  resumed_by_default: false

bytes_per_token =  case System.get_env("BYTES_PER_TOKEN") do
  nil -> 100
  env -> String.to_integer(env)
end

config :aecore, :tx_data,
  lock_time_coinbase: 10,
  miner_fee_bytes_per_token: bytes_per_token,
  pool_fee_bytes_per_token: 100
