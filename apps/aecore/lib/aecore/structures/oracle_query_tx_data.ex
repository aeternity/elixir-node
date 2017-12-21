defmodule Aecore.Structures.OracleQueryTxData do

  alias __MODULE__
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.OraclePrototype.OracleTxValidation

  require Logger

  defstruct [:sender,
             :oracle_hash,
             :query_data,
             :query_fee,
             :fee]

  @spec create(binary(), map(), integer(), integer()) :: %OracleQueryTxData{}
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
        %OracleQueryTxData{sender: pubkey, oracle_hash: oracle_hash,
                           query_data: query_data, query_fee: query_fee,
                           fee: fee}
    end
  end
end
