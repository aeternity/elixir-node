defmodule Aecore.Governance.GenesisConstants do
  @moduledoc """
  Module containing genesis block constants
  """

  @prev_hash <<0::256>>

  @txs_hash <<0::256>>

  @time 0

  @height 0

  @nonce 0

  @miner <<0::256>>

  @version 15

  @target 0x2100FFFF

  @evidence :no_value

  @spec prev_hash :: binary()
  def prev_hash, do: @prev_hash

  @spec txs_hash :: binary()
  def txs_hash, do: @txs_hash

  @spec time :: non_neg_integer()
  def time, do: @time

  @spec height :: non_neg_integer()
  def height, do: @height

  @spec nonce :: non_neg_integer()
  def nonce, do: @nonce

  @spec miner :: binary()
  def miner, do: @miner

  @spec version :: non_neg_integer()
  def version, do: @version

  @spec target :: non_neg_integer
  def target, do: @target

  @spec evidence :: atom()
  def evidence, do: @evidence
end
