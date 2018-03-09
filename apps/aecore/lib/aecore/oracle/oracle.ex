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
  also has a description field that gives string information about the oracle,
  an oracle uri is passed as the last argument which is mapped to the node's
  registered oracles, whenever a query references one of the node's registered
  oracles, the transaction is posted to the uri.
  """
  @spec register(map(), map(), binary(), integer()) :: :ok | :error
  def register(query_format, response_format, description, fee) do
    case OracleRegistrationTxData.create(query_format, response_format, description, fee) do
      :error ->
        :error

      tx_data ->
        signed_tx = sign_tx(tx_data)
        signed_tx_hash = SignedTx.hash_tx(signed_tx)

        Pool.add_transaction(signed_tx)
    end
  end

  @doc """
  Creates a query transaction with the given registered oracle hash, data query
  and a fee that is given to the oracle. It also has a fee field like every
  other transaction.
  """
  @spec query(binary(), any(), integer(), integer()) :: :ok | :error
  def query(oracle_address, query_data, query_fee, response_fee) do
    case OracleQueryTxData.create(oracle_address, query_data, query_fee, response_fee) do
      :error ->
        :error

      tx_data ->
        Pool.add_transaction(sign_tx(tx_data))
    end
  end

  @doc """
  Creates an oracle response transaction with the oracle referenced by its
  transaction hash and the data of the response.
  """
  @spec respond(binary(), any(), integer()) :: :ok | :error
  def respond(oracle_address, response, fee) do
    case OracleResponseTxData.create(oracle_address, response, fee) do
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
