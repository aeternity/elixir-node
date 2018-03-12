defmodule Aecore.Oracle.Oracle do
  alias Aecore.Structures.OracleRegistrationTxData
  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Structures.OracleResponseTxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Txs.Pool.Worker, as: Pool

  require Logger

  @doc """
  Registers an oracle with the given requirements for queries and responses,
  a fee that should be paid by queries and a TTL.
  """
  @spec register(map(), map(), integer(), integer()) :: :ok | :error
  def register(query_format, response_format, query_fee, ttl) do
    case OracleRegistrationTxData.create(query_format, response_format, query_fee, ttl) do
      :error ->
        :error

      tx_data ->
        signed_tx = sign_tx(tx_data)
        Pool.add_transaction(signed_tx)
    end
  end

  @doc """
  Creates a query transaction with the given oracle address, data query
  and a TTL of the query and response.
  """
  @spec query(binary(), any(), integer(), integer()) :: :ok | :error
  def query(oracle_address, query_data, query_ttl, response_ttl) do
    case OracleQueryTxData.create(
           oracle_address,
           query_data,
           query_ttl,
           response_ttl
         ) do
      :error ->
        :error

      tx_data ->
        Pool.add_transaction(sign_tx(tx_data))
    end
  end

  @doc """
  Creates an oracle response transaction with the query referenced by its
  transaction hash and the data of the response.
  """
  @spec respond(binary(), any(), integer()) :: :ok | :error
  def respond(query_hash, response, fee) do
    case OracleResponseTxData.create(query_hash, response, fee) do
      :error ->
        :error

      tx_data ->
        Pool.add_transaction(sign_tx(tx_data))
    end
  end

  @spec data_valid?(map(), map()) :: true | false
  def data_valid?(format, data) do
    schema = ExJsonSchema.Schema.resolve(format)

    case ExJsonSchema.Validator.validate(schema, data) do
      :ok ->
        true

      {:error, message} ->
        Logger.error(message)
        false
    end
  end

  @spec sign_tx(map()) :: %SignedTx{}
  defp sign_tx(data) do
    {:ok, signature} = Keys.sign(data)
    %SignedTx{signature: signature, data: data}
  end
end
