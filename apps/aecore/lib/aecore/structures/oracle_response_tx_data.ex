defmodule Aecore.Structures.OracleResponseTxData do
  alias __MODULE__
  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys

  require Logger

  @type t :: %OracleResponseTxData{
          operator: binary(),
          query_hash: binary(),
          response: map(),
          fee: non_neg_integer(),
          nonce: non_neg_integer()
        }

  defstruct [:operator, :query_hash, :response, :fee, :nonce]
  use ExConstructor

  @spec create(binary(), any(), integer()) :: OracleResponseTxData.t()
  def create(query_hash, response, fee) do
    {:ok, pubkey} = Keys.pubkey()
    registered_oracles = Chain.registered_oracles()
    response_format = registered_oracles[pubkey].data.response_format

    interaction_object = Chain.oracle_interaction_objects()[query_hash]

    valid_query_hash =
      if interaction_object != nil do
        interaction_object.response == nil
      else
        false
      end

    cond do
      !valid_query_hash ->
        Logger.error("Invalid query hash")
        :error

      !Oracle.data_valid?(response_format, response) ->
        :error

      true ->
        %OracleResponseTxData{
          operator: pubkey,
          query_hash: query_hash,
          response: response,
          fee: fee,
          nonce: Chain.lowest_valid_nonce()
        }
    end
  end
end
