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
  params: {"./lean", "-t 5", 28},
  max_difficulty_change: 1,
  genesis_header: %{
    height: 0,
    prev_hash: <<0::256>>,
    txs_hash: <<0::256>>,
    chain_state_hash: <<0 :: 256>>,
    timestamp: 1_507_275_094_308,
    nonce: 9,
    pow_evidence: [323365363266, 353739636235, 363662373537,
                   646363313138, 656130393433, 31333933393961,
                   31393937343036, 31623065323931, 31623733333132,
                   31633931663734, 31643834653065, 32303362303763,
                   32353235346333, 32353561353439, 32633365623637,
                   32643065373865, 32666238393832, 33366464396538,
                   34306461666636, 34353062366265, 34353965666136,
                   34613833333330, 34633163653737, 34636364666335,
                   34646132356336, 34646538393737, 34656137366466,
                   35326366346131, 35353166646436, 35396438333232,
                   35663063363135, 36303439363939, 36313365343436,
                   36316631343461, 36336134666631, 36336238613364,
                   36633132303833, 37316633613662, 37383336306430,
                   37653232326463, 37656632303139, 37663863663639],

    version: 1,
    difficulty_target: 1
  }

config :aecore, :peers,
  peers_target_count: 25,
  peers_max_count: 50

config :aecore, :miner,
  resumed_by_default: true

config :aecore, :tx_data,
  miner_fee_bytes_per_token: 100,
  pool_fee_bytes_per_token: 100
