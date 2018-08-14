defmodule Aecore.Governance.GovernanceConstants do
  @moduledoc """
  Aecore structure to provide governance constants.
  """

  @number_of_blocks_for_target_recalculation 10

  # 30sec
  @expected_mine_rate_ms 30_000

  @coinbase_transaction_amount 10_000_000_000_000_000_000

  # 30min
  @time_validation_future_limit_ms 1_800_000

  @split_name_symbol "."

  @name_registrars [@split_name_symbol <> "aet", @split_name_symbol <> "test"]

  @pre_claim_ttl 300

  @revoke_expiration_ttl 2016

  @client_ttl_limit 86_400

  @claim_expire_by_relative_limit 50_000

  # Genesis block constants
  @genesis_prev_hash <<0::256>>

  @genesis_txs_hash <<0::256>>

  @genesis_time 0

  @genesis_height 0

  @genesis_nonce 0

  @genesis_miner <<0::256>>

  @genesis_version 15

  @genesis_target 0x2100FFFF

  @genesis_evidence :no_value

  # getter functions with same name for use in other modules

  @spec number_of_blocks_for_target_recalculation :: non_neg_integer()
  def number_of_blocks_for_target_recalculation, do: @number_of_blocks_for_target_recalculation

  @spec expected_mine_rate_ms :: non_neg_integer()
  def expected_mine_rate_ms, do: @expected_mine_rate_ms

  @spec coinbase_transaction_amount :: non_neg_integer()
  def coinbase_transaction_amount, do: @coinbase_transaction_amount

  @spec time_validation_future_limit_ms :: non_neg_integer()
  def time_validation_future_limit_ms, do: @time_validation_future_limit_ms

  @spec split_name_symbol :: String.t()
  def split_name_symbol, do: @split_name_symbol

  @spec name_registrars :: list(String.t())
  def name_registrars, do: @name_registrars

  @spec pre_claim_ttl :: non_neg_integer()
  def pre_claim_ttl, do: @pre_claim_ttl

  @spec revoke_expiration_ttl :: non_neg_integer()
  def revoke_expiration_ttl, do: @revoke_expiration_ttl

  @spec client_ttl_limit :: non_neg_integer()
  def client_ttl_limit, do: @client_ttl_limit

  @spec claim_expire_by_relative_limit :: non_neg_integer()
  def claim_expire_by_relative_limit, do: @claim_expire_by_relative_limit

  @spec genesis_prev_hash :: binary()
  def genesis_prev_hash, do: @genesis_prev_hash

  @spec genesis_txs_hash :: binary()
  def genesis_txs_hash, do: @genesis_txs_hash

  @spec genesis_time :: non_neg_integer()
  def genesis_time, do: @genesis_time

  @spec genesis_height :: non_neg_integer()
  def genesis_height, do: @genesis_height

  @spec genesis_nonce :: non_neg_integer()
  def genesis_nonce, do: @genesis_nonce

  @spec genesis_miner :: binary()
  def genesis_miner, do: @genesis_miner

  @spec genesis_version :: non_neg_integer()
  def genesis_version, do: @genesis_version

  @spec genesis_target :: non_neg_integer
  def genesis_target, do: @genesis_target

  @spec genesis_evidence :: atom()
  def genesis_evidence, do: @genesis_evidence
end
