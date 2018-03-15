defmodule Aecore.Structures.OracleQueryTxData do
  alias __MODULE__
  alias Aecore.Structures.SignedTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Oracle.Oracle
  alias Aeutil.Bits

  require Logger

  @type t :: %OracleQueryTxData{
          sender: binary(),
          oracle_address: binary(),
          query_data: map(),
          query_fee: non_neg_integer(),
          fee: non_neg_integer(),
          query_ttl: Oracle.ttl(),
          response_ttl: Oracle.ttl(),
          nonce: non_neg_integer()
        }

  @nonce_size 256

  defstruct [
    :sender,
    :oracle_address,
    :query_data,
    :query_fee,
    :fee,
    :query_ttl,
    :response_ttl,
    :nonce
  ]

  use ExConstructor

  @spec create(binary(), any(), integer(), Oracle.ttl(), Oracle.ttl()) :: OracleQueryTxData.t()
  def create(oracle_address, query_data, fee, query_ttl, response_ttl) do
    registered_oracles = Chain.registered_oracles()

    cond do
      !Map.has_key?(registered_oracles, oracle_address) ->
        Logger.error("No oracle registered with that address")
        :error

      !Oracle.data_valid?(
        registered_oracles[oracle_address].tx.query_format,
        query_data
      ) ->
        :error

      true ->
        {:ok, pubkey} = Keys.pubkey()

        %OracleQueryTxData{
          sender: pubkey,
          oracle_address: oracle_address,
          query_data: query_data,
          query_fee: get_oracle_query_fee(oracle_address),
          fee: fee,
          query_ttl: query_ttl,
          response_ttl: response_ttl,
          nonce: Chain.lowest_valid_nonce()
        }
    end
  end

  @spec get_oracle_query_fee(binary()) :: integer()
  def get_oracle_query_fee(oracle_address) do
    Chain.registered_oracles()[oracle_address].tx.query_fee
  end

  @spec calculate_minimum_fee(integer()) :: integer()
  def calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_query_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end

  @spec is_minimum_fee_met?(SignedTx.t(), integer()) :: boolean()
  def is_minimum_fee_met?(tx, block_height) do
    tx_query_fee_is_met =
      tx.data.query_fee >= Chain.registered_oracles()[tx.data.oracle_address].tx.query_fee

    tx_fee_is_met =
      case tx.data.query_ttl do
        %{ttl: ttl, type: :relative} ->
          tx.data.fee >= calculate_minimum_fee(ttl)

        %{ttl: ttl, type: :absolute} ->
          if block_height != nil do
            tx.data.fee >=
              ttl
              |> Oracle.calculate_relative_ttl(block_height)
              |> calculate_minimum_fee()
          else
            true
          end
      end

    tx_fee_is_met && tx_query_fee_is_met
  end

  @spec id(SignedTx.t()) :: binary()
  def id(%SignedTx{data: %{sender: sender, oracle_address: oracle_address, nonce: nonce}}) do
    bin = sender <> <<nonce::@nonce_size>> <> oracle_address
    :crypto.hash(:sha256, bin)
  end

  @spec bech32_encode(binary()) :: String.t()
  def bech32_encode(bin) do
    Bits.bech32_encode("qy", bin)
  end
end
