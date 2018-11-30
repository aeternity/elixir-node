defmodule Aecore.Governance.GovernanceConstants do
  @moduledoc """
  Module containing governance constants
  """

  @protocol_version 29

  @micro_block_distance 3000

  @number_of_blocks_for_target_recalculation 17

  # 60sec * 1000ms * 5 = 300_000ms
  @expected_mine_rate_ms 300_000

  @coinbase_transaction_amount 10_000_000_000_000_000_000
  @current_generation_fee_reward_multiplier 0.4
  @previous_generation_fee_reward_multiplier 0.6
  @beneficiary_reward_lock_time 180

  @minimum_fee 1

  @oracle_register_base_fee 4
  @oracle_query_base_fee 2
  @oracle_response_base_fee 2
  @oracle_extend_base_fee 1

  @block_gas_limit 6_000_000

  @oracle_ttl_fee_per_block 0.001

  # 30min
  @time_validation_future_limit_ms 1_800_000

  @split_name_symbol "."

  @name_registrars [@split_name_symbol <> "test"]

  @pre_claim_ttl 300

  @revoke_expiration_ttl 2016

  @client_ttl_limit 86_400

  @claim_expire_by_relative_limit 50_000

  @name_split_check 2

  @name_claim_burned_fee 3

  @max_txs_per_block 10_946

  @default_tx_gas_price 15_000

  @known_tx_types [
    Aecore.Account.Tx.SpendTx,
    Aecore.Channel.Tx.ChannelCloseMutualTx,
    Aecore.Channel.Tx.ChannelCloseSoloTx,
    Aecore.Channel.Tx.ChannelCreateTx,
    Aecore.Channel.Tx.ChannelDepositTx,
    Aecore.Channel.Tx.ChannelSettleTx,
    Aecore.Channel.Tx.ChannelSlashTx,
    Aecore.Channel.Tx.ChannelWithdrawTx,
    Aecore.Contract.Tx.ContractCallTx,
    Aecore.Contract.Tx.ContractCreateTx,
    Aecore.Naming.Tx.NameClaimTx,
    Aecore.Naming.Tx.NamePreClaimTx,
    Aecore.Naming.Tx.NameRevokeTx,
    Aecore.Naming.Tx.NameTransferTx,
    Aecore.Naming.Tx.NameUpdateTx,
    Aecore.Oracle.Tx.OracleExtendTx,
    Aecore.Oracle.Tx.OracleQueryTx,
    Aecore.Oracle.Tx.OracleRegistrationTx,
    Aecore.Oracle.Tx.OracleResponseTx
  ]

  # getter functions with same name for use in other modules

  @spec protocol_version :: non_neg_integer()
  def protocol_version, do: @protocol_version

  @spec micro_block_distance :: non_neg_integer()
  def micro_block_distance, do: @micro_block_distance

  @spec number_of_blocks_for_target_recalculation :: non_neg_integer()
  def number_of_blocks_for_target_recalculation, do: @number_of_blocks_for_target_recalculation

  @spec expected_mine_rate_ms :: non_neg_integer()
  def expected_mine_rate_ms, do: @expected_mine_rate_ms

  @spec coinbase_transaction_amount :: non_neg_integer()
  def coinbase_transaction_amount, do: @coinbase_transaction_amount

  @spec current_generation_fee_reward_multiplier :: float()
  def current_generation_fee_reward_multiplier, do: @current_generation_fee_reward_multiplier

  @spec previous_generation_fee_reward_multiplier :: float()
  def previous_generation_fee_reward_multiplier, do: @previous_generation_fee_reward_multiplier

  @spec beneficiary_reward_lock_time :: non_neg_integer()
  def beneficiary_reward_lock_time, do: @beneficiary_reward_lock_time

  @spec minimum_fee :: non_neg_integer()
  def minimum_fee, do: @minimum_fee

  @spec oracle_register_base_fee :: non_neg_integer()
  def oracle_register_base_fee, do: @oracle_register_base_fee

  @spec oracle_query_base_fee :: non_neg_integer()
  def oracle_query_base_fee, do: @oracle_query_base_fee

  @spec oracle_response_base_fee :: non_neg_integer()
  def oracle_response_base_fee, do: @oracle_response_base_fee

  @spec oracle_extend_base_fee :: non_neg_integer()
  def oracle_extend_base_fee, do: @oracle_extend_base_fee

  @spec oracle_ttl_fee_per_block :: float()
  def oracle_ttl_fee_per_block, do: @oracle_ttl_fee_per_block

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

  @spec name_split_check :: non_neg_integer()
  def name_split_check, do: @name_split_check

  @spec name_claim_burned_fee :: non_neg_integer()
  def name_claim_burned_fee, do: @name_claim_burned_fee

  @spec max_txs_per_block :: non_neg_integer()
  def max_txs_per_block, do: @max_txs_per_block

  @spec block_gas_limit :: non_neg_integer()
  def block_gas_limit, do: @block_gas_limit

  @spec default_tx_gas_price :: non_neg_integer()
  def default_tx_gas_price, do: @default_tx_gas_price

  @spec default_tx_gas_price :: list()
  def get_valid_txs_type, do: @known_tx_types
end
