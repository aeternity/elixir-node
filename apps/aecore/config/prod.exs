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
    pow_evidence: [827_073, 968_001, 1_367_727,
                   2_248_958, 2_496_250, 3_450_285,
                   3_762_239, 4_330_454, 4_753_400,
                   6_298_861, 7_633_605, 8_406_300,
                   8_427_108, 8_637_289, 9_074_181,
                   11_812_624, 12_065_013, 12_379_945,
                   12_636_125, 13_185_509, 13_304_773,
                   16_291_222, 16_913_907, 17_967_337,
                   18_585_455, 19_550_321, 19_557_538,
                   21_486_461, 21_542_527, 22_115_004,
                   22_608_952, 22_961_192, 23_009_944,
                   24_049_559, 24_093_275, 24_618_494,
                   24_790_930, 24_863_623, 25_203_962,
                   26_777_546, 27_127_749, 29_049_875],
    version: 1,
    difficulty_target: 1
  }

config :aecore, :peers,
  peers_target_count: 25,
  peers_max_count: 50
