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
  nil -> "apps/aecore/priv/rox_db/"
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
    nonce: 304,
    pow_evidence:
      [383737, 616161, 623333, 653164, 663632, 31303565, 31333936,
      31336163, 31366633, 31386437, 31613832, 31633235, 32326637, 32333235,
      32336337, 32383039, 32633234, 33303136, 33363732, 33373436, 33396366,
      34316464, 34376137, 34393162, 34653465, 34663031, 35303132, 35306366,
      35346664, 36343336, 36393136, 36396538, 36613461, 36623066, 36633134,
      36633766, 36663432, 36666664, 37363561, 37393762, 37633162, 37643561],

    version: 1,
    difficulty_target: 1
  }

config :aecore, :peers,
  peers_target_count: 5,
  peers_max_count: 8

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

config :aecore, :block,
  max_block_size_bytes: 500_000
