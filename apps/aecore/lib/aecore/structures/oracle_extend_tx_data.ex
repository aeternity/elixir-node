defmodule Aecore.Structures.OracleExtendTxData do
  alias __MODULE__
  alias Aecore.Chain.Worker, as: Chain

  require Logger

  @type t :: %OracleExtendTxData{
          oracle_address: binary(),
          ttl: non_neg_integer(),
          fee: non_neg_integer(),
          nonce: non_neg_integer()
        }

  defstruct [:oracle_address, :ttl, :fee, :nonce]
  use ExConstructor

  def create(oracle_address, ttl, fee) do
    registered_oracles = Chain.registered_oracles()

    cond do
      !Map.has_key?(registered_oracles, oracle_address) ->
        Logger.error("No oracle registered with that address")
        :error

      !(ttl > 0) ->
        Logger.error("TTL extend value can't be negative")
        :error

      true ->
        %OracleExtendTxData{
          oracle_address: oracle_address,
          ttl: ttl,
          fee: fee,
          nonce: Chain.lowest_valid_nonce()
        }
    end
  end

  @spec calculate_minimum_fee(integer()) :: integer()
  def calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_extend_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
