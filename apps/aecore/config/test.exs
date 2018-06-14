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

config :aecore, :persistence, path: persistence_path |> Path.absname() |> Path.join("//")

config :aecore, :pow,
  new_candidate_nonce_count: 10,
  bin_dir: Path.absname("apps/aecore/priv/cuckoo/bin"),
  params: {"./lean16", "-t 5", 16},
  max_target_change: 0,
  genesis_header: %{
    height: 0,
    prev_hash: <<0::256>>,
    txs_hash: <<0::256>>,
    root_hash: <<0::256>>,
    time: 1_507_275_094_308,
    nonce: 46,
    miner: <<0::256>>,
    pow_evidence: [
      1656,
      2734,
      2879,
      3388,
      4324,
      7350,
      7500,
      8237,
      8383,
      8970,
      9791,
      9799,
      13460,
      14799,
      16196,
      18360,
      18395,
      18815,
      19037,
      19181,
      19819,
      19824,
      21921,
      22577,
      22823,
      22943,
      24148,
      24883,
      24996,
      25922,
      26228,
      26358,
      26475,
      26804,
      27998,
      28638,
      29706,
      30489,
      30759,
      31453,
      31562,
      32630
    ],
    version: 1,
    target: 0x2100FFFF
  }

config :aecore, :peers,
  peers_target_count: 2,
  peers_max_count: 4

config :aecore, :miner, resumed_by_default: false

config :aecore, :tx_data,
  minimum_fee: 1,
  max_txs_per_block: 100,
  blocks_ttl_per_token: 1000,
  oracle_registration_base_fee: 4,
  oracle_query_base_fee: 2,
  oracle_response_base_fee: 2,
  oracle_extend_base_fee: 1
