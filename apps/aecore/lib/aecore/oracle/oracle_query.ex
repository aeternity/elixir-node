defmodule Aecore.Oracle.OracleQuery do
  @moduledoc """
  Defines oracle query structure
  """

  alias Aecore.Oracle.OracleQuery
  alias Aecore.Keys.Wallet
  alias Aecore.Tx.DataTx
  alias Aeutil.Serialization
  alias Aecore.Chain.Identifier

  @version 1

  @type t :: %OracleQuery{
          expires: integer(),
          fee: integer(),
          has_response: boolean(),
          oracle_address: binary(),
          query: binary(),
          response: map() | atom(),
          response_ttl: integer(),
          sender_address: Wallet.pubkey(),
          sender_nonce: integer()
        }

  defstruct [
    :expires,
    :fee,
    :has_response,
    :oracle_address,
    :query,
    :response,
    :response_ttl,
    :sender_address,
    :sender_nonce
  ]

  use ExConstructor
  use Aecore.Util.Serializable

  def encode_to_list(%OracleQuery{} = oracle_query) do
    has_response =
      case oracle_query.has_response do
        true -> 1
        false -> 0
      end

    response =
      case oracle_query.response do
        :undefined -> "undefined"
        %DataTx{type: OracleResponseTx} = data -> data
        _ -> oracle_query.response
      end

    [
      @version,
      Identifier.encode_to_binary(oracle_query.sender_address),
      oracle_query.sender_nonce,
      Identifier.encode_to_binary(oracle_query.oracle_address),
      oracle_query.query,
      has_response,
      response,
      oracle_query.expires,
      oracle_query.response_ttl,
      oracle_query.fee
    ]
  end

  def decode_from_list(@version, [
        encoded_sender_address,
        sender_nonce,
        encoded_oracle_address,
        query,
        has_response,
        response,
        expires,
        response_ttl,
        fee
      ]) do
    has_response =
      case Serialization.transform_item(has_response, :int) do
        1 -> true
        0 -> false
      end

    new_response =
      case response do
        "undefined" -> :undefined
        _ -> response
      end

    with {:ok, oracle_address} <- Identifier.decode_from_binary(encoded_oracle_address),
         {:ok, sender_address} <- Identifier.decode_from_binary(encoded_sender_address) do
      {:ok,
       %OracleQuery{
         expires: Serialization.transform_item(expires, :int),
         fee: Serialization.transform_item(fee, :int),
         has_response: has_response,
         oracle_address: oracle_address,
         query: query,
         response: new_response,
         response_ttl: Serialization.transform_item(response_ttl, :int),
         sender_address: sender_address,
         sender_nonce: Serialization.transform_item(sender_nonce, :int)
       }}
    else
      {:error, _} = error -> error
    end
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
