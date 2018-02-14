defmodule Aecore.Structures.OracleRegistrationSpendTx do

  alias __MODULE__
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Chain.Worker, as: Chain

  require Logger

  @type t :: %OracleRegistrationSpendTx{
    operator: binary(),
    query_format: map(),
    response_format: map(),
    description: String.t(),
    fee: non_neg_integer(),
    nonce: non_neg_integer()
  }

  defstruct [:operator,
             :query_format,
             :response_format,
             :description,
             :fee,
             :nonce]
  use ExConstructor

  @spec create(map(), map(), binary(), integer()) :: %OracleRegistrationSpendTx{}
  def create(query_format, response_format, description, fee) do
    try do
      ExJsonSchema.Schema.resolve(query_format)
      ExJsonSchema.Schema.resolve(response_format)
      {:ok, pubkey} = Keys.pubkey()
      %OracleRegistrationSpendTx{operator: pubkey,
                                query_format: query_format,
                                response_format: response_format,
                                description: description,
                                fee: fee, nonce: Chain.lowest_valid_nonce()}
    rescue
      e ->
       Logger.error("Invalid query or response format definition; " <> e.message)
       :error
    end
  end
end
