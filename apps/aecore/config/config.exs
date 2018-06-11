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
path = Path.absname("apps/aecore")
%{year: year, month: month, day: day} = DateTime.utc_now()
time = "#{year}-#{month}-#{day}_"

persistence_path =
  case System.get_env("PERSISTENCE_PATH") do
    nil -> "apps/aecore/priv/rox_db/"
    env -> env
  end

aewallet_pass =
  case System.get_env("AEWALLET_PASS") do
    nil -> " "
    env -> env
  end

aewallet_path =
  case System.get_env("AEWALLET_PATH") do
    nil -> "apps/aecore/priv/aewallet"
    env -> env
  end

config :aecore, :spend_tx, version: 1

config :aecore, :aewallet, pub_key_size: 33

config :aecore, :rlp_tags,
  account_state: 10,
  signed_tx: 11,
  spend_tx: 12,
  registered_orc_state: 20,
  interaction_obj_state: 21,
  oracle_reg_tx: 22,
  oracle_query_tx: 23,
  oracle_response_tx: 24,
  oracle_extend_tx: 25,
  naming_state: 30,
  name_commitment_state: 31,
  name_claim_tx: 32,
  name_pre_claim_tx: 33,
  name_update_tx: 34,
  name_revoke_tx: 35,
  name_transfer_tx: 36,
  block: 100

config :aecore, :version, block: 14

config :aecore, :bytes_size,
  txs_hash: 32,
  state_hash: 32,
  miner_pubkey: 32,
  header_hash: 32,
  root_hash: 32,
  pow_total_size: 168

config :aecore, :signed_tx, sign_max_size: 72

config :aecore, :oracle_response_tx, query_id: 32

config :aecore, :naming,
  max_label_length: 63,
  max_name_length: 253

config :aecore, :aewallet,
  pass: aewallet_pass,
  path: Path.absname(aewallet_path)

config :aecore, :persistence,
  path: persistence_path |> Path.absname() |> Path.join("//"),
  number_of_blocks_in_memory: 100,
  write_options: [sync: true, disable_wal: false]

config :logger,
  compile_time_purge_level: :info,
  backends: [:console, {LoggerFileBackend, :info}, {LoggerFileBackend, :error}]

config :logger, :console, level: :error

config :logger, :info,
  path: path <> "/logs/#{time}info.log",
  level: :info

config :logger, :error,
  path: path <> "/logs/#{time}error.log",
  level: :error

import_config "#{Mix.env()}.exs"
