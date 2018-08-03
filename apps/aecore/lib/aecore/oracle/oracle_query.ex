defmodule Aecore.Oracle.OracleQuery do
  @moduledoc """
  Defines oracle query structure
  """

  alias Aecore.Oracle.OracleQuery
  alias Aecore.Keys.Wallet
  alias Aeutil.Parser
  alias Aecore.Tx.DataTx
  alias Aeutil.Serialization

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
        :undefined -> Parser.to_string(:undefined)
        %DataTx{type: OracleResponseTx} = data -> DataTx.rlp_encode(data)
        %{} = data -> Poison.encode!(data)
      end

    [
      @version,
      oracle_query.sender_address,
      oracle_query.sender_nonce,
      oracle_query.oracle_address,
      Serialization.transform_item(oracle_query.query),
      has_response,
      response,
      oracle_query.expires,
      oracle_query.response_ttl,
      oracle_query.fee
    ]
  end

  def decode_from_list(
        @version,
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
        ]
      ) do
    has_response =
      case Serialization.transform_item(has_response, :int) do
        1 -> true
        0 -> false
      end

    new_response =
      case response do
        "undefined" -> String.to_atom(response)
        _ -> Serialization.transform_item(response, :binary)
      end

    {:ok,
     %OracleQuery{
       expires: Serialization.transform_item(expires, :int),
       fee: Serialization.transform_item(fee, :int),
       has_response: has_response,
       oracle_address: oracle_address,
       query: Serialization.transform_item(query, :binary),
       response: new_response,
       response_ttl: Serialization.transform_item(response_ttl, :int),
       sender_address: sender_address,
       sender_nonce: Serialization.transform_item(sender_nonce, :int)
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end

  def rlp_encode(%OracleQuery{} = oracle_query) do
    Serialization.rlp_encode(oracle_query)
  end

  def rlp_decode(binary) do
    Serialization.rlp_decode_only(binary, OracleQuery)
  end
end
