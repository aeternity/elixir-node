defmodule Aecore.Oracle.Oracle do
  alias Aecore.Structures.OracleRegistrationTxData
  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Structures.OracleResponseTxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Txs.Pool.Worker, as: Pool

  require Logger

  @type ttl :: %{ttl: non_neg_integer(), type: :relative | :absolute}

  @doc """
  Registers an oracle with the given requirements for queries and responses,
  a fee that should be paid by queries and a TTL.
  """
  @spec register(map(), map(), integer(), integer(), ttl()) :: :ok | :error
  def register(query_format, response_format, query_fee, fee, ttl) do
    case OracleRegistrationTxData.create(query_format, response_format, query_fee, fee, ttl) do
      :error ->
        :error

      tx_data ->
        Pool.add_transaction(sign_tx(tx_data))
    end
  end

  @doc """
  Creates a query transaction with the given oracle address, data query
  and a TTL of the query and response.
  """
  @spec query(binary(), any(), integer(), ttl(), ttl()) :: :ok | :error
  def query(oracle_address, query_data, fee, query_ttl, response_ttl) do
    case OracleQueryTxData.create(
           oracle_address,
           query_data,
           fee,
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
  def respond(query_id, response, fee) do
    case OracleResponseTxData.create(query_id, response, fee) do
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

  @spec calculate_absolute_ttl(ttl(), integer()) :: integer()
  def calculate_absolute_ttl(%{ttl: ttl, type: type}, block_height_tx_included) do
    case type do
      :absolute ->
        ttl

      :relative ->
        ttl + block_height_tx_included
    end
  end

  @spec calculate_relative_ttl(%{ttl: integer(), type: :absolute}, integer()) :: integer()
  def calculate_relative_ttl(%{ttl: ttl, type: :absolute}, block_height) do
    ttl - block_height
  end

  @spec is_tx_ttl_valid?(SignedTx.t(), integer()) :: boolean
  def is_tx_ttl_valid?(tx, block_height) do
    case tx.data do
      %OracleRegistrationTxData{} ->
        ttl_is_valid?(tx.data.ttl, block_height)

      %OracleQueryTxData{} ->
        response_ttl_is_valid =
          case tx.data.response_ttl do
            %{ttl: _, type: :absolute} ->
              Logger.error("Response TTL has to be relative")
              false

            %{ttl: _, type: :relative} ->
              ttl_is_valid?(tx.data.response_ttl, block_height)
          end

        query_ttl_is_valid = ttl_is_valid?(tx.data.query_ttl, block_height)

        response_ttl_is_valid && query_ttl_is_valid

      _ ->
        true
    end
  end

  defp ttl_is_valid?(%{ttl: ttl, type: type}, block_height) do
    case type do
      :absolute ->
        ttl - block_height > 0

      :relative ->
        ttl > 0
    end
  end

  @spec sign_tx(map()) :: %SignedTx{}
  defp sign_tx(data) do
    {:ok, signature} = Keys.sign(data)
    %SignedTx{signature: signature, data: data}
  end
end
