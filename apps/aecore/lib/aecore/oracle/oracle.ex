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
  @spec register(map(), map(), non_neg_integer(), non_neg_integer(), ttl()) :: :ok | :error
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
  @spec query(binary(), any(), non_neg_integer(), non_neg_integer(), ttl(), ttl()) :: :ok | :error
  def query(oracle_address, query_data, query_fee, fee, query_ttl, response_ttl) do
    payload = %{
      oracle_address: oracle_address,
      query_data: query_data,
      query_fee: query_fee,
      query_ttl: query_ttl,
      response_ttl: response_ttl
    }

    tx_data =
      DataTx.init(
        OracleQueryTxData,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @doc """
  Creates an oracle response transaction with the query referenced by its
  transaction hash and the data of the response.
  """
  @spec respond(binary(), any(), non_neg_integer()) :: :ok | :error
  def respond(query_id, response, fee) do
    payload = %{
      query_id: query_id,
      response: response
    }

    tx_data =
      DataTx.init(
        OracleResponseTxData,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @spec extend(non_neg_integer(), non_neg_integer()) :: :ok | :error
  def extend(ttl, fee) do
    payload = %{
      ttl: ttl
    }

    tx_data =
      DataTx.init(
        OracleExtendTxData,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_private_key())
    Pool.add_transaction(tx)
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

  @spec calculate_absolute_ttl(ttl(), non_neg_integer()) :: non_neg_integer()
  def calculate_absolute_ttl(%{ttl: ttl, type: type}, block_height_tx_included) do
    case type do
      :absolute ->
        ttl

      :relative ->
        ttl + block_height_tx_included
    end
  end

  @spec calculate_relative_ttl(%{ttl: non_neg_integer(), type: :absolute}, non_neg_integer()) ::
          non_neg_integer()
  def calculate_relative_ttl(%{ttl: ttl, type: :absolute}, block_height) do
    ttl - block_height
  end

  @spec tx_ttl_is_valid?(SignedTx.t(), non_neg_integer()) :: boolean
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

  def remove_expired_oracles(chain_state, block_height) do
    Enum.reduce(chain_state.oracles.registered_oracles, chain_state, fn {address,
                                                                         %{
                                                                           tx: tx,
                                                                           height_included:
                                                                             height_included
                                                                         }},
                                                                        acc ->
      if calculate_absolute_ttl(tx.ttl, height_included) <= block_height do
        acc
        |> pop_in([:oracles, :registered_oracles, address])
        |> elem(1)
      else
        acc
      end
    end)
  end

  def remove_expired_interaction_objects(
        chain_state,
        block_height
      ) do
    Enum.reduce(chain_state.oracles.interaction_objects, chain_state, fn {query_id,
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

      query_has_expired = query_absolute_ttl <= block_height && response == nil

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
          acc
          |> update_in(
            [:accounts, query_sender, :balance],
            &(&1 + query.query_fee)
          )
          |> pop_in([:oracles, :interaction_objects, query_id])
          |> elem(1)

        response_has_expired ->
          acc
          |> pop_in([:oracles, :interaction_objects, query_id])
          |> elem(1)

        true ->
          acc
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
end
