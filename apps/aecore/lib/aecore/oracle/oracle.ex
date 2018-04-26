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

    {:ok, tx} = SignedTx.sign_tx(tx_data, Wallet.get_private_key())
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
        OracleResponseTx,
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
        OracleExtendTx,
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
                                                                           tx: tx,
                                                                           height_included:
                                                                             height_included
                                                                         }},
                                                                        acc ->
      if calculate_absolute_ttl(tx.ttl, height_included) <= block_height do
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
                                                        query: query,
                                                        query_sender: query_sender,
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
            calculate_absolute_ttl(query.query_ttl, response_height_included)

          response_absolute_ttl <= block_height
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

  def rlp_encode(
        %Chainstate{oracles: %{registered_oracles: registered_oracles}},
        orc_owner,
        :oracle_state
      ) do
    # list_of_formatted_data =
    # Subject to discuss field "height_included" in our structures is not being encoded , erlang" core doesnt have this field
    case Map.get(registered_oracles, orc_owner) do
      nil ->
        [
          type_to_tag(Oracle),
          get_version(Oracle),
          orc_owner, # owner
          Serialization.transform_item(%{}), #query_format, should be a string(but we have a map)
          Serialization.transform_item(%{}), #response_format, should be a string (but we have a map)
          0, #query_fee
          0, #expires
        ]

      data ->
        [
          type_to_tag(Oracle),
          get_version(Oracle),
          orc_owner,  # owner
          # Subject to discuss/change - In Erlang implementation its a UTF8 encoded string but in our case - map
          Serialization.transform_item(data.tx.query_format), #query_format, should be a string(but we have a map)
          Serialization.transform_item(data.tx.response_format), #response_format, should be a string (but we have a map)
          data.tx.query_fee, #query_fee
          # Subject to discuss/change - Erlang core has an integer field called expires, our case - map with ttl and its type :absolute/relative
         # encode_ttl_type(data.tx.ttl),
          data.tx.ttl.ttl  #"expires" doesnt exist at this moment,
        ]
    end
    |> ExRLP.encode()
  end
  def rlp_encode(
        %Chainstate{oracles: %{interaction_objects: interaction_objects}},
        sender_address,
        :oracle_query
      ) do
    case Map.get(interaction_objects, sender_address) do
      nil ->
        [
          type_to_tag(OracleQuery), #type
          get_version(OracleQuery), #ver
          sender_address, #pubkey
          0, #sender_nonce
          <<0>>, # oracle_address
          Serialization.transform_item(%OracleQueryTx{}), #query
          <<0>>, #has_response
          Serialization.transform_item(%OracleResponseTx{}), #response
          0, #expires
          0, #response_ttl
          0, #fee
        ]

      data ->
        [
          type_to_tag(OracleQuery), #type
          get_version(OracleQuery), #ver
          sender_address, #pubkey
          # Subject : We dont have sender_nonce field here,
          data.query.oracle_address, # oracle_address
          # Subject : Query: Equivalent here would be fully composed DataTx(OracleQueryTx) , not just OracleQueryTx
          DataTx.rlp_encode(Serialization.transform_item(data.query)), #query
          <<0>>,  # Subject: has_response field doesnt exist, will be hardcoded as <<0>>/false for now
          # Subject: Response: Equivalent here would be fully composed DataTx(ResponseTx), not a map
          DataTx.rlp_encode(Serialization.transform_item(data.query.response)), #response
          data.query.query_ttl.ttl, # Subject: no field called "expires" here, should be calculated over ttl_type and ttl_value itself
          data.query.response_ttl.ttl,
          data.query.query_fee
        ]
    end
    |> ExRLP.encode()
  end
  def rlp_encode(_) do
    :invalid_oracle_struct
  end
  @spec rlp_decode(binary()) :: {:ok, Account.t()} | Block.t() | DataTx.t()
  def rlp_decode(values) when is_binary(values) do
    [tag_bin, ver_bin | rest_data] = ExRLP.decode(values)
    tag = Serialization.transform_item(tag_bin, :int)
    ver = Serialization.transform_item(ver_bin, :int)
    case type_to_tag(tag) do
        Oracle ->
          [orc_owner, query_format, response_format, query_fee, ttl_type, ttl] = rest_data

        [
          orc_owner,
          Serialization.transform_item(query_format, :binary),
          Serialization.transform_item(response_format, :binary),
          Serialization.transform_item(query_fee, :int),
          Serialization.transform_item(ttl_type, :int),
          Serialization.transform_item(ttl, :int)
        ]
       OracleQuery ->
        [sender_address,oracle_address,query_data,has_response, query_response, expires,response_ttl,query_fee] = rest_data
        
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
