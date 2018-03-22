defmodule Aecore.Oracle.Oracle do
  alias Aecore.Structures.OracleRegistrationTxData
  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Structures.OracleResponseTxData
  alias Aecore.Structures.OracleExtendTxData
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain

  require Logger

  @type ttl :: %{ttl: non_neg_integer(), type: :relative | :absolute}

  @doc """
  Registers an oracle with the given requirements for queries and responses,
  a fee that should be paid by queries and a TTL.
  """
  @spec register(map(), map(), integer(), integer(), ttl()) :: :ok | :error
  def register(query_format, response_format, query_fee, fee, ttl) do
    payload = %{
      query_format: query_format,
      response_format: response_format,
      query_fee: query_fee,
      ttl: ttl
    }

    tx_data =
      DataTx.init(
        OracleRegistrationTxData,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_private_key())
    Pool.add_transaction(tx)
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

  @spec extend(binary(), integer(), integer()) :: :ok | :error
  def extend(oracle_address, ttl, fee) do
    case OracleExtendTxData.create(oracle_address, ttl, fee) do
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

      {:error, [{message, _}]} ->
        Logger.error(fn -> message end)
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

  @spec tx_ttl_is_valid?(SignedTx.t(), integer()) :: boolean
  def tx_ttl_is_valid?(tx, block_height) do
    case tx do
      %OracleRegistrationTxData{} ->
        ttl_is_valid?(tx.ttl, block_height)

      %OracleQueryTxData{} ->
        response_ttl_is_valid =
          case tx.response_ttl do
            %{type: :absolute} ->
              Logger.error("Response TTL has to be relative")
              false

            %{type: :relative} ->
              ttl_is_valid?(tx.response_ttl, block_height)
          end

        query_ttl_is_valid = ttl_is_valid?(tx.query_ttl, block_height)

        response_ttl_is_valid && query_ttl_is_valid

      %OracleExtendTxData{} ->
        tx.ttl > 0

      _ ->
        true
    end
  end

  @spec ttl_is_valid?(ttl()) :: boolean()
  def ttl_is_valid?(ttl) do
    case ttl do
      %{ttl: ttl, type: :absolute} ->
        ttl > 0

      %{ttl: ttl, type: :relative} ->
        ttl > 0

      _ ->
        Logger.error("Invalid TTL definition")
        false
    end
  end

  def remove_expired_oracles(oracles, block_height) do
    Enum.reduce(oracles, oracles, fn {address, %{tx: tx, height_included: height_included}},
                                     acc ->
      if calculate_absolute_ttl(tx.ttl, height_included) == block_height do
        Map.delete(acc, address)
      else
        acc
      end
    end)
  end

  def remove_expired_interaction_objects(
        oracle_interaction_objects,
        block_height,
        accounts
      ) do
    Enum.reduce(oracle_interaction_objects, oracle_interaction_objects, fn {query_tx_hash,
                                                                            %{
                                                                              query: query,
                                                                              query_sender:
                                                                                query_sender,
                                                                              response: response,
                                                                              query_height_included:
                                                                                query_height_included,
                                                                              response_height_included:
                                                                                response_height_included
                                                                            }},
                                                                           acc ->
      query_absolute_ttl =
        calculate_absolute_ttl(
          query.query_ttl,
          query_height_included
        )

      query_has_expired = query_absolute_ttl == block_height && response == nil

      response_has_expired =
        if response != nil do
          response_absolute_ttl =
            calculate_absolute_ttl(
              query.query_ttl,
              response_height_included
            )

          response_absolute_ttl == block_height
        else
          false
        end

      cond do
        query_has_expired ->
          {put_in(
             accounts,
             [query_sender, :balance],
             get_in(accounts, [query_sender, :balance]) + query.query_fee
           ), Map.delete(acc, query_tx_hash)}

        response_has_expired ->
          {accounts, Map.delete(acc, query_tx_hash)}

        true ->
          {accounts, acc}
      end
    end)
  end

  defp ttl_is_valid?(%{ttl: ttl, type: type}, block_height) do
    case type do
      :absolute ->
        ttl - block_height > 0

      :relative ->
        ttl > 0
    end
  end

  defp sign_tx(data) do
    {:ok, signature} = Keys.sign(data)
    %SignedTx{signature: signature, data: data}
  end
end
