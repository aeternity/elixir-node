defmodule Aecore.Structures.OracleQuerySpendTx do

  alias __MODULE__
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.OraclePrototype.OracleTxValidation

  require Logger

  @type t :: %OracleQuerySpendTx{
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

  @spec create(binary(), map(), integer(), integer()) :: %OracleQuerySpendTx{}
  def create(oracle_hash, query_data, query_fee, fee) do
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
        %OracleQuerySpendTx{sender: pubkey, oracle_hash: oracle_hash,
                           query_data: query_data, query_fee: query_fee,
                           fee: fee, nonce: Chain.lowest_valid_nonce()}
    end
  end
end
