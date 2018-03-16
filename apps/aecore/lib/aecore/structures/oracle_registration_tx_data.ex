defmodule Aecore.Structures.OracleRegistrationTxData do
  alias __MODULE__
  alias Aecore.Structures.SignedTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Oracle.Oracle
  alias Aeutil.Bits

  require Logger

  @type t :: %OracleRegistrationTxData{
          operator: binary(),
          query_format: map(),
          response_format: map(),
          query_fee: non_neg_integer(),
          fee: non_neg_integer(),
          ttl: Oracle.ttl(),
          nonce: non_neg_integer()
        }

  defstruct [
    :operator,
    :query_format,
    :response_format,
    :query_fee,
    :fee,
    :ttl,
    :nonce
  ]

  use ExConstructor

  @spec create(map(), map(), integer(), integer(), Oracle.ttl()) :: OracleRegistrationTxData.t()
  def create(query_format, response_format, query_fee, fee, ttl) do
    {:ok, pubkey} = Keys.pubkey()

    cond do
      Map.has_key?(Chain.registered_oracles(), pubkey) ->
        Logger.error("Account is already an oracle")
        :error

      !Oracle.ttl_is_valid?(ttl) ->
        :error

      true ->
        try do
          ExJsonSchema.Schema.resolve(query_format)
          ExJsonSchema.Schema.resolve(response_format)
        rescue
          e ->
            Logger.error("Invalid query or response format definition; " <> e.message)

            :error
        end

        %OracleRegistrationTxData{
          operator: pubkey,
          query_format: query_format,
          response_format: response_format,
          query_fee: query_fee,
          fee: fee,
          ttl: ttl,
          nonce: Chain.lowest_valid_nonce()
        }
    end
  end

  @spec is_minimum_fee_met?(SignedTx.t(), integer()) :: boolean()
  def is_minimum_fee_met?(tx, block_height) do
    case tx.data.ttl do
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
  end

  @spec bech32_encode(binary()) :: String.t()
  def bech32_encode(bin) do
    Bits.bech32_encode("or", bin)
  end

  @spec calculate_minimum_fee(integer()) :: integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]

    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_registration_base_fee]

    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
