defmodule Aecore.Structures.OracleResponseTxData do
  alias __MODULE__
  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys

  require Logger

  @type t :: %OracleResponseTxData{
          operator: binary(),
          query_id: binary(),
          response: map(),
          fee: non_neg_integer(),
          nonce: non_neg_integer()
        }

  defstruct [:operator, :query_id, :response, :fee, :nonce]
  use ExConstructor

  @spec create(binary(), any(), integer()) :: OracleResponseTxData.t()
  def create(query_id, response, fee) do
    {:ok, pubkey} = Keys.pubkey()
    registered_oracles = Chain.registered_oracles()
    response_format = registered_oracles[pubkey].tx.response_format

    interaction_object = Chain.oracle_interaction_objects()[query_id]

    valid_query_id =
      if interaction_object != nil do
        interaction_object.response == nil && interaction_object.query.oracle_address == pubkey
      else
        false
      end

    cond do
      !valid_query_id ->
        Logger.error("Invalid query referenced")
        :error

      !Oracle.data_valid?(response_format, response) ->
        :error

      true ->
        %OracleResponseTxData{
          operator: pubkey,
          query_id: query_id,
          response: response,
          fee: fee,
          nonce: Chain.lowest_valid_nonce()
        }
    end
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    referenced_query_response_ttl =
      Chain.oracle_interaction_objects()[tx.data.query_id].query.response_ttl

    tx.data.fee >= calculate_minimum_fee(referenced_query_response_ttl)
  end

  @spec calculate_minimum_fee(integer()) :: integer()
  defp calculate_minimum_fee(ttl) do
    blocks_ttl_per_token = Application.get_env(:aecore, :tx_data)[:blocks_ttl_per_token]
    base_fee = Application.get_env(:aecore, :tx_data)[:oracle_response_base_fee]
    round(Float.ceil(ttl / blocks_ttl_per_token) + base_fee)
  end
end
