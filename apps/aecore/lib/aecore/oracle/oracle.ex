defmodule Aecore.Oracle.Oracle do
  @moduledoc """
  Contains wrapping functions for working with oracles, data validation and TTL calculations.
  """

  alias Aecore.Oracle.Tx.OracleRegistrationTx
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Oracle.Tx.OracleResponseTx
  alias Aecore.Oracle.Tx.OracleExtendTx
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Serialization
  alias Aeutil.Parser
  alias ExJsonSchema.Schema, as: JsonSchema
  alias ExJsonSchema.Validator, as: JsonValidator

  require Logger

  @type oracle_txs_with_ttl :: OracleRegistrationTx.t() | OracleQueryTx.t() | OracleExtendTx.t()

  @type json_schema :: map()
  @type json :: any()

  @type registered_oracles :: %{
          Wallet.pubkey() => %{
            tx: OracleRegistrationTx.t(),
            height_included: non_neg_integer()
          }
        }

  @type interaction_objects :: %{
          OracleQueryTx.id() => %{
            query: OracleQueryTx.t(),
            response: OracleResponseTx.t(),
            query_height_included: non_neg_integer(),
            response_height_included: non_neg_integer()
          }
        }

  @type t :: %{
          registered_oracles: registered_oracles(),
          interaction_objects: interaction_objects()
        }

  @type ttl :: %{ttl: non_neg_integer(), type: :relative | :absolute}

  @doc """
  Registers an oracle with the given requirements for queries and responses,
  a fee that should be paid by queries and a TTL.
  """
  @spec register(
          json_schema(),
          json_schema(),
          non_neg_integer(),
          non_neg_integer(),
          ttl(),
          non_neg_integer()
        ) :: :ok | :error
  def register(query_format, response_format, query_fee, fee, ttl, tx_ttl \\ 0) do
    payload = %{
      query_format: query_format,
      response_format: response_format,
      query_fee: query_fee,
      ttl: ttl
    }

    tx_data =
      DataTx.init(
        OracleRegistrationTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce(),
        tx_ttl
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @doc """
  Creates a query transaction with the given oracle address, data query
  and a TTL of the query and response.
  """
  @spec query(
          Wallet.pubkey(),
          json(),
          non_neg_integer(),
          non_neg_integer(),
          ttl(),
          ttl(),
          non_neg_integer()
        ) :: :ok | :error
  def query(oracle_address, query_data, query_fee, fee, query_ttl, response_ttl, tx_ttl \\ 0) do
    payload = %{
      oracle_address: oracle_address,
      query_data: query_data,
      query_fee: query_fee,
      query_ttl: query_ttl,
      response_ttl: response_ttl
    }

    tx_data =
      DataTx.init(
        OracleQueryTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce(),
        tx_ttl
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @doc """
  Creates an oracle response transaction with the query referenced by its
  transaction hash and the data of the response.
  """
  @spec respond(binary(), any(), non_neg_integer(), non_neg_integer()) :: :ok | :error
  def respond(query_id, response, fee, tx_ttl \\ 0) do
    payload = %{
      query_id: query_id,
      response: response
    }

    tx_data =
      DataTx.init(
        OracleResponseTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce(),
        tx_ttl
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @spec extend(non_neg_integer(), non_neg_integer(), non_neg_integer()) :: :ok | :error
  def extend(ttl, fee, tx_ttl \\ 0) do
    payload = %{
      ttl: ttl
    }

    tx_data =
      DataTx.init(
        OracleExtendTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce(),
        tx_ttl
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @spec data_valid?(map(), map()) :: true | false
  def data_valid?(format, data) do
    schema = JsonSchema.resolve(format)

    case JsonValidator.validate(schema, data) do
      :ok ->
        true

      {:error, [{message, _}]} ->
        Logger.error(fn -> "#{__MODULE__}: " <> message end)
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

  @spec tx_ttl_is_valid?(oracle_txs_with_ttl() | SignedTx.t(), non_neg_integer()) :: boolean
  def tx_ttl_is_valid?(tx, block_height) do
    case tx do
      %OracleRegistrationTx{} ->
        ttl_is_valid?(tx.ttl, block_height)

      %OracleQueryTx{} ->
        response_ttl_is_valid =
          case tx.response_ttl do
            %{type: :absolute} ->
              Logger.error("#{__MODULE__}: Response TTL has to be relative")
              false

            %{type: :relative} ->
              ttl_is_valid?(tx.response_ttl, block_height)
          end

        query_ttl_is_valid = ttl_is_valid?(tx.query_ttl, block_height)

        response_ttl_is_valid && query_ttl_is_valid

      %OracleExtendTx{} ->
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
        Logger.error("#{__MODULE__}: Invalid TTL definition")
        false
    end
  end

  def remove_expired_oracles(chain_state, block_height) do
    Enum.reduce(chain_state.oracles.registered_oracles, chain_state, fn {address,
                                                                         %{
                                                                           expires: expiry_height
                                                                         }},
                                                                        acc ->
      if expiry_height <= block_height do
        acc
        |> pop_in([Access.key(:oracles), Access.key(:registered_oracles), address])
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
    interaction_objects = chain_state.oracles.interaction_objects

    Enum.reduce(interaction_objects, chain_state, fn {query_id,
                                                      %{
                                                        sender_address: sender_address,
                                                        has_response: has_response,
                                                        expires: expires,
                                                        fee: fee
                                                      }},
                                                     acc ->
      if expires <= block_height do
        updated_state =
          acc
          |> pop_in([:oracles, :interaction_objects, query_id])
          |> elem(1)

        if has_response do
          updated_state
        else
          update_in(updated_state, [:accounts, sender_address, :balance], &(&1 + fee))
        end
      else
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

  @spec rlp_encode(
          non_neg_integer(),
          non_neg_integer(),
          map(),
          :registered_oracle | :interaction_object
        ) :: binary()
  def rlp_encode(tag, version, %{} = registered_oracle, :registered_oracle) do
    list = [
      tag,
      version,
      registered_oracle.owner,
      Serialization.transform_item(registered_oracle.query_format),
      Serialization.transform_item(registered_oracle.response_format),
      registered_oracle.query_fee,
      registered_oracle.expires
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  def rlp_encode(tag, version, %{} = interaction_object, :interaction_object) do
    has_response =
      case interaction_object.has_response do
        true -> 1
        false -> 0
      end

    response =
      case interaction_object.response do
        :undefined -> Parser.to_string(:undefined)
        %DataTx{type: OracleResponseTx} = data -> data
      end

    list = [
      tag,
      version,
      interaction_object.sender_address,
      interaction_object.sender_nonce,
      interaction_object.oracle_address,
      Serialization.transform_item(interaction_object.query),
      has_response,
      response,
      interaction_object.expires,
      interaction_object.response_ttl,
      interaction_object.fee
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  def rlp_encode(data) do
    {:error, "#{__MODULE__}: Invalid Oracle struct #{inspect(data)}"}
  end

  @spec rlp_decode(list(), :registered_oracle | :interaction_object) ::
          {:ok, map()} | {:error, String.t()}
  def rlp_decode(
        [orc_owner, query_format, response_format, query_fee, expires],
        :registered_oracle
      ) do
    {:ok,
     %{
       owner: orc_owner,
       query_format: Serialization.transform_item(query_format, :binary),
       response_format: Serialization.transform_item(response_format, :binary),
       query_fee: Serialization.transform_item(query_fee, :int),
       expires: Serialization.transform_item(expires, :int)
     }}
  end

  def rlp_decode(
        [
          sender_address,
          sender_nonce,
          oracle_address,
          query,
          has_response,
          response,
          expires,
          response_ttl,
          fee
        ],
        :interaction_object
      ) do
    has_response =
      case Serialization.transform_item(has_response, :int) do
        1 -> true
        0 -> false
      end

    {:ok,
     %{
       expires: Serialization.transform_item(expires, :int),
       fee: Serialization.transform_item(fee, :int),
       has_response: has_response,
       oracle_address: oracle_address,
       query: Serialization.transform_item(query, :binary),
       response: response,
       response_ttl: Serialization.transform_item(response_ttl, :int),
       sender_address: sender_address,
       sender_nonce: Serialization.transform_item(sender_nonce, :int)
     }}
  end

  def rlp_decode(_) do
    {:error,
     "#{__MODULE__}Illegal Registered oracle state / Oracle interaction object serialization"}
  end
end
