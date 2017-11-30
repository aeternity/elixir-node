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
  nif_path: Path.absname("apps/aecore/priv/cuckoo/aec_pow_cuckoo20_nif"),
  genesis_header: %{
    height: 0,
    prev_hash: <<0::256>>,
    txs_hash: <<0::256>>,
    chain_state_hash: <<0 :: 256>>,
    timestamp: 1_507_275_094_308,
    nonce: 62,
    pow_evidence: [5_865, 33_461, 43_503, 72_290,
                   97_096, 102_579, 109_935, 110_807,
                   129_404, 135_480, 145_736, 174_409,
                   178_611, 180_359, 183_866, 197_227,
                   198_055, 206_373, 220_794, 221_908,
                   227_792, 240_266, 248_610, 311_225,
                   312_038, 315_739, 327_595, 334_270,
                   336_439, 345_186, 348_916, 357_090,
                   372_159, 444_132, 462_404, 464_127,
                   464_504, 495_627, 495_985, 497_109,
                   504_460, 510_965],
    version: 1,
    difficulty_target: 1
  }

config :aecore, :peers,
  peers_target_count: 3,
  peers_max_count: 4

config :aecore, :tx_data,
  lock_time_block: 10
