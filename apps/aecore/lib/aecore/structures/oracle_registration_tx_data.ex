defmodule Aecore.Structures.OracleRegistrationTxData do
  alias __MODULE__
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Bits

  require Logger

  @type t :: %OracleRegistrationTxData{
          operator: binary(),
          query_format: map(),
          response_format: map(),
          query_fee: non_neg_integer(),
          fee: non_neg_integer(),
          ttl: non_neg_integer(),
          nonce: non_neg_integer()
        }

  defstruct [:operator, :query_format, :response_format, :query_fee, :fee, :ttl, :nonce]
  use ExConstructor

  @spec create(map(), map(), integer(), integer()) :: OracleRegistrationTxData.t()
  def create(query_format, response_format, query_fee, ttl) do
    try do
      ExJsonSchema.Schema.resolve(query_format)
      ExJsonSchema.Schema.resolve(response_format)
    rescue
      e ->
        Logger.error("Invalid query or response format definition; " <> e.message)
        :error
    end

    {:ok, pubkey} = Keys.pubkey()

    %OracleRegistrationTxData{
      operator: pubkey,
      query_format: query_format,
      response_format: response_format,
      query_fee: query_fee,
      fee: calculate_minimum_fee(ttl),
      ttl: ttl,
      nonce: Chain.lowest_valid_nonce()
    }
  end

  @spec calculate_minimum_fee(integer()) :: integer()
  def calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_reg_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end

  @spec bech32_encode(binary()) :: String.t()
  def bech32_encode(bin) do
    Bits.bech32_encode("or", bin)
  end
end
