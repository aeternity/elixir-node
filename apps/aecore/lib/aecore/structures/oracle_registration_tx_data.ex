defmodule Aecore.Structures.OracleRegistrationTxData do

  alias __MODULE__
  alias Aecore.Keys.Worker, as: Keys

  require Logger

  defstruct [:operator,
             :query_format,
             :response_format,
             :description,
             :fee]

  @spec create(map(), map(), binary(), integer()) :: %OracleRegistrationTxData{}
  def create(query_format, response_format, description, fee) do
    try do
      ExJsonSchema.Schema.resolve(query_format)
      ExJsonSchema.Schema.resolve(response_format)
      {:ok, pubkey} = Keys.pubkey()
      %OracleRegistrationTxData{operator: pubkey,
                                query_format: query_format,
                                response_format: response_format,
                                description: description, fee: fee}
    rescue
      e ->
       Logger.error("Invalid query or response format definition; " <> e.message)
       :error
    end

  end
end
