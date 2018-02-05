defmodule Aecore.Structures.OracleRegistrationTxData do

  alias __MODULE__
  alias Aecore.Keys.Worker, as: Keys

  require Logger

  defstruct [:operator,
             :query_format,
             :response_format,
             :description,
             :fee,
             :nonce]
  use ExConstructor

  @spec create(map(), map(), binary(), integer(), integer()) :: %OracleRegistrationTxData{}
  def create(query_format, response_format, description, fee, nonce) do
    try do
      ExJsonSchema.Schema.resolve(query_format)
      ExJsonSchema.Schema.resolve(response_format)
      {:ok, pubkey} = Keys.pubkey()
      %OracleRegistrationTxData{operator: pubkey,
                                query_format: query_format,
                                response_format: response_format,
                                description: description,
                                fee: fee, nonce: nonce}
    rescue
      e ->
       Logger.error("Invalid query or response format definition; " <> e.message)
       :error
    end
  end

  @spec is_oracle_registration_tx(map()) :: boolean()
  def is_oracle_registration_tx(tx) do
    Map.has_key?(tx, "operator") && Map.has_key?(tx, "query_format") &&
    Map.has_key?(tx, "response_format") && Map.has_key?(tx, "description") &&
    Map.has_key?(tx, "fee") && Map.has_key?(tx, "nonce")
  end
end
