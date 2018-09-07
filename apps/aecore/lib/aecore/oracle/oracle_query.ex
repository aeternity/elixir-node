defmodule Aecore.Oracle.OracleQuery do
  @moduledoc """
  Module defining the structure of an OracleQuery
  """

  alias Aecore.Oracle.OracleQuery
  alias Aecore.Keys
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
          sender_address: Keys.pubkey(),
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
        true -> <<1>>
        false -> <<0>>
      end

    response =
      case oracle_query.response do
        :undefined -> <<>>
        %DataTx{type: OracleResponseTx} = data -> data
        _ -> oracle_query.response
      end

    [
      :binary.encode_unsigned(@version),
      oracle_query.sender_address,
      :binary.encode_unsigned(oracle_query.sender_nonce),
      oracle_query.oracle_address,
      oracle_query.query,
      has_response,
      response,
      :binary.encode_unsigned(oracle_query.expires),
      :binary.encode_unsigned(oracle_query.response_ttl),
      :binary.encode_unsigned(oracle_query.fee)
    ]
  end

  def decode_from_list(@version, [
        sender_address,
        sender_nonce,
        oracle_address,
        query,
        has_response,
        response,
        expires,
        response_ttl,
        fee
      ]) do
    has_response =
      case has_response do
        <<1>> -> true
        <<0>> -> false
      end

    new_response =
      case response do
        <<>> -> :undefined
        _ -> response
      end

    {:ok,
     %OracleQuery{
       expires: :binary.decode_unsigned(expires),
       fee: :binary.decode_unsigned(fee),
       has_response: has_response,
       oracle_address: oracle_address,
       query: query,
       response: new_response,
       response_ttl: :binary.decode_unsigned(response_ttl),
       sender_address: sender_address,
       sender_nonce: :binary.decode_unsigned(sender_nonce)
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
