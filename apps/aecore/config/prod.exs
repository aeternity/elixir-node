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
  path: Path.absname(persistence_path)

config :aecore, :pow,
  nif_path: Path.absname("apps/aecore/priv/cuckoo/aec_pow_cuckoo26_nif"),
  genesis_header: %{
    height: 0,
    prev_hash: <<0::256>>,
    txs_hash: <<0::256>>,
    chain_state_hash: <<0 :: 256>>,
    timestamp: 1_507_275_094_308,
    nonce: 49,
    pow_evidence: [827073, 968001, 1367727,
                   2248958, 2496250, 3450285,
                   3762239, 4330454, 4753400,
                   6298861, 7633605, 8406300,
                   8427108, 8637289, 9074181,
                   11812624, 12065013, 12379945,
                   12636125, 13185509, 13304773,
                   16291222, 16913907, 17967337,
                   18585455, 19550321, 19557538,
                   21486461, 21542527, 22115004,
                   22608952, 22961192, 23009944,
                   24049559, 24093275, 24618494,
                   24790930, 24863623, 25203962,
                   26777546, 27127749, 29049875],
    version: 1,
    difficulty_target: 1
  }

config :aecore, :peers,
  peers_target_count: 25,
  peers_max_count: 50
