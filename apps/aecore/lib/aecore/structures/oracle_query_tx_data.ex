defmodule Aecore.Structures.OracleQueryTxData do

  alias __MODULE__
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.OraclePrototype.OracleTxValidation

  require Logger

  @type t :: %OracleQueryTxData{
    sender: binary(),
    oracle_hash: binary(),
    query_data: map(),
    query_fee: non_neg_integer(),
    fee: non_neg_integer(),
    nonce: non_neg_integer()
  }

  defstruct [:sender,
             :oracle_hash,
             :query_data,
             :query_fee,
             :fee,
             :nonce]
  use ExConstructor

  @spec create(binary(), map(), integer(), integer(), integer()) :: %OracleQueryTxData{}
  def create(oracle_hash, query_data, query_fee, fee, nonce) do
    registered_oracles = Chain.registered_oracles()
    query_format = registered_oracles[oracle_hash].data.query_format
    cond do
      !Map.has_key?(registered_oracles, oracle_hash) ->
        Logger.error("No oracle registered with that hash")
        :error
      !OracleTxValidation.data_valid?(query_format, query_data) ->
        :error
      true ->
        {:ok, pubkey} = Keys.pubkey()
        %OracleQueryTxData{sender: pubkey, oracle_hash: oracle_hash,
                           query_data: query_data, query_fee: query_fee,
                           fee: fee, nonce: nonce}
    end
  end

  @spec is_oracle_query_tx(map()) :: boolean()
  def is_oracle_query_tx(tx) do
    Map.has_key?(tx, "sender") && Map.has_key?(tx, "oracle_hash") &&
    Map.has_key?(tx, "query_data") && Map.has_key?(tx, "query_fee") &&
    Map.has_key?(tx, "fee") && Map.has_key?(tx, "nonce")
  end
end
