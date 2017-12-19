defmodule Aecore.Structures.OracleQueryTxData do

  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain

  require Logger

  defstruct [:sender,
             :oracle_hash,
             :query_data,
             :query_fee,
             :fee]

  def create(oracle_hash, query_data, query_fee, fee) do
    registered_oracles = Chain.registered_oracles()
    cond do
      !Map.has_key?(registered_oracles, oracle_hash) ->
        {:error, "No oracle registered with that hash"}
      !validate_query_data(registered_oracles[oracle_hash].data.query_format, query_data) ->
        {:error, "Invalid query format"}
      true ->
        {:ok, pubkey} = Keys.pubkey()
        %OracleQueryTxData{sender: pubkey, oracle_hash: oracle_hash,
                           query_data: query_data, query_fee: query_fee,
                           fee: fee}
    end
  end

  def validate_query_data(schema, data) do
    valid_types = ["number", "integer", "string", "array", "boolean"]
    case schema["type"] do
      "object" ->
        if(Map.keys(schema["properties"]) == Map.keys(data)) do
          ExJsonSchema.Validator.valid?(schema, data)
        else
          false
        end
      type ->
        if(Enum.member?(valid_types, type)) do
          ExJsonSchema.Validator.valid?(schema, data)
        else
          false
        end
    end
  end
end
