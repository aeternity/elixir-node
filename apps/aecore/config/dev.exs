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

persistence_path =
  case System.get_env("PERSISTENCE_PATH") do
    nil -> "apps/aecore/priv/rox_db/"
    env -> env
  end

new_candidate_nonce_count =
  case System.get_env("NEW_CANDIDATE_NONCE_COUNT") do
    nil -> 10
    env -> env
  end

config :aecore, :persistence,
  path: Path.absname(persistence_path),
  write_options: [sync: true, disable_wal: false]

config :aecore, :pow,
  new_candidate_nonce_count: new_candidate_nonce_count,
  bin_dir: Path.absname("apps/aecore/priv/cuckoo/bin"),
  params: {"./lean", "-t 5", 16},
  max_target_change: 1,
  genesis_header: %{
    height: 0,
    prev_hash: <<0::256>>,
    txs_hash: <<0::256>>,
    root_hash: <<0::256>>,
    time: 1_507_275_094_308,
    nonce: 304,
    pow_evidence: [
      383_737,
      616_161,
      623_333,
      653_164,
      663_632,
      31_303_565,
      31_333_936,
      31_336_163,
      31_366_633,
      31_386_437,
      31_613_832,
      31_633_235,
      32_326_637,
      32_333_235,
      32_336_337,
      32_383_039,
      32_633_234,
      33_303_136,
      33_363_732,
      33_373_436,
      33_396_366,
      34_316_464,
      34_376_137,
      34_393_162,
      34_653_465,
      34_663_031,
      35_303_132,
      35_306_366,
      35_346_664,
      36_343_336,
      36_393_136,
      36_396_538,
      36_613_461,
      36_623_066,
      36_633_134,
      36_633_766,
      36_663_432,
      36_666_664,
      37_363_561,
      37_393_762,
      37_633_162,
      37_643_561
    ],
    version: 1,
    target: 0x2100FFFF
  }

config :aecore, :peers,
  peers_target_count: 5,
  peers_max_count: 8

config :aecore, :miner, resumed_by_default: false

bytes_per_token =
  case System.get_env("BYTES_PER_TOKEN") do
    nil -> 100
    env -> String.to_integer(env)
  end

config :aecore, :tx_data,
  minimum_fee: 10,
  max_txs_per_block: 100,
  blocks_ttl_per_token: 1000,
  oracle_registration_base_fee: 4,
  oracle_query_base_fee: 2,
  oracle_response_base_fee: 2,
  oracle_extend_base_fee: 1
