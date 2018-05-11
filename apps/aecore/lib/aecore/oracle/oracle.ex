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
  alias Aecore.Account.Account
  alias Aecore.Chain.Chainstate
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
  @spec register(json_schema(), json_schema(), non_neg_integer(), non_neg_integer(), ttl()) ::
          :ok | :error
  def register(query_format, response_format, query_fee, fee, ttl) do
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
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @doc """
  Creates a query transaction with the given oracle address, data query
  and a TTL of the query and response.
  """
  @spec query(Account.pubkey(), json(), non_neg_integer(), non_neg_integer(), ttl(), ttl()) ::
          :ok | :error
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
        OracleQueryTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
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
        OracleResponseTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
      )

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_public_key(), Wallet.get_private_key())
    Pool.add_transaction(tx)
  end

  @spec extend(non_neg_integer(), non_neg_integer()) :: :ok | :error
  def extend(ttl, fee) do
    payload = %{
      ttl: ttl
    }

    tx_data =
      DataTx.init(
        OracleExtendTx,
        payload,
        Wallet.get_public_key(),
        fee,
        Chain.lowest_valid_nonce()
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

  @spec tx_ttl_is_valid?(oracle_txs_with_ttl(), non_neg_integer()) :: boolean
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

  @spec rlp_encode(map(), atom()) :: binary()
  def rlp_encode(%{} = registered_oracle, :registered_oracle) do
    [
      type_to_tag(Oracle),
      get_version(Oracle),
      # owner
      registered_oracle.owner,
      # query_format, currently is a map
      Poison.encode!(registered_oracle.query_format),
      # response_format, currently is a map
      Poison.encode!(registered_oracle.response_format),
      # query_fee
      registered_oracle.query_fee,
      # expires
      registered_oracle.expires
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%{} = interaction_object, :interaction_object) do
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

    [
      # type
      type_to_tag(OracleQuery),
      # ver
      get_version(OracleQuery),
      # pubkey
      interaction_object.sender_address,
      # sender_nonce
      interaction_object.sender_nonce,
      # oracle_address
      interaction_object.oracle_address,
      # query
      Poison.encode!(interaction_object.query),
      # has_response
      has_response,
      DataTx.rlp_encode(response),
      # Subject: no field called "expires" here, should be calculated over ttl_type and ttl_value itself
      interaction_object.expires,
      interaction_object.response_ttl,
      interaction_object.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(_) do
    {:error, "Invalid Oracle struct"}
  end

  @spec rlp_decode(binary()) :: {:ok, Account.t()} | Block.t() | DataTx.t()
  def rlp_decode(values) when is_binary(values) do
    [tag_bin, ver_bin | rest_data] = ExRLP.decode(values)
    tag = Serialization.transform_item(tag_bin, :int)
    ver = Serialization.transform_item(ver_bin, :int)

    case tag_to_type(tag) do
      Oracle ->
        [orc_owner, query_format, response_format, query_fee, expires] = rest_data

        {:ok,
         %{
           owner: orc_owner,
           # Poison encodings might be changed in future
           query_format: Poison.decode!(query_format),
           response_format: Poison.decode!(response_format),
           query_fee: Serialization.transform_item(query_fee, :int),
           expires: Serialization.transform_item(expires, :int)
         }}

      OracleQuery ->
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
        ] = rest_data

        has_response =
          case Serialization.transform_item(has_response, :int) do
            1 -> true
            0 -> false
          end

        response =
          case ExRLP.decode(response) do
            [] -> DataTx.rlp_decode(response)
            data -> String.to_atom(data)
          end

        {:ok,
         %{
           expires: Serialization.transform_item(expires, :int),
           fee: Serialization.transform_item(fee, :int),
           has_response: has_response,
           oracle_address: oracle_address,
           query: Poison.decode!(query),
           response: response,
           response_ttl: Serialization.transform_item(response_ttl, :int),
           sender_address: sender_address,
           sender_nonce: Serialization.transform_item(sender_nonce, :int)
         }}

      _ ->
        {:error, "Illegal Registered oracle state / Oracle interaction object serialization"}
    end
  end

  @spec type_to_tag(atom()) :: integer
  defp type_to_tag(Oracle), do: 20
  defp type_to_tag(OracleQuery), do: 21

  @spec tag_to_type(integer()) :: atom()
  defp tag_to_type(20), do: Oracle
  defp tag_to_type(21), do: OracleQuery

  defp get_version(Oracle), do: 1
  defp get_version(OracleQuery), do: 1
end
