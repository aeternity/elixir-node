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
config :aecore, :persistence,
  table: Path.absname("apps/aecore/priv/persistence_table")

config :aecore, :pow,
  nif_path: Path.absname("apps/aecore/priv/aec_pow_cuckoo20_nif"),
  genesis_header: %{
    height: 0,
    prev_hash: <<0::256>>,
    txs_hash: <<0::256>>,
    chain_state_hash: <<0 :: 256>>,
    timestamp: 1_507_275_094_308,
    nonce: 62,
    pow_evidence: [5865, 33461, 43503, 72290,
                   97096, 102579, 109935, 110807,
                   129404, 135480, 145736, 174409,
                   178611, 180359, 183866, 197227,
                   198055, 206373, 220794, 221908,
                   227792, 240266, 248610, 311225,
                   312038, 315739, 327595, 334270,
                   336439, 345186, 348916, 357090,
                   372159, 444132, 462404, 464127,
                   464504, 495627, 495985, 497109,
                   504460, 510965],
    version: 1,
    difficulty_target: 1
  }
