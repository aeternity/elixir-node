defmodule Aecore.Oracle.OracleQuery do
  @moduledoc """
  Module defining the structure of an OracleQuery
  """

  alias Aecore.Oracle.OracleQuery
  alias Aecore.Keys
  alias Aeutil.Serialization

  @version 1

  @typedoc "Reason of the error"
  @type reason :: String.t()

  @typedoc "Structure of the Query type"
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

  @spec encode_to_list(OracleQuery.t()) :: list()
  def encode_to_list(%OracleQuery{
        sender_address: sender_address,
        has_response: has_response,
        sender_nonce: sender_nonce,
        response: response,
        oracle_address: oracle_address,
        query: query,
        expires: expires,
        response_ttl: response_ttl,
        fee: fee
      }) do
    serialized_has_response =
      if has_response do
        <<1>>
      else
        <<0>>
      end

    serialized_response =
      case response do
        :undefined -> <<>>
        _ -> response
      end

    [
      :binary.encode_unsigned(@version),
      sender_address,
      :binary.encode_unsigned(sender_nonce),
      oracle_address,
      query,
      serialized_has_response,
      serialized_response,
      :binary.encode_unsigned(expires),
      :binary.encode_unsigned(response_ttl),
      :binary.encode_unsigned(fee)
    ]
  end

  @spec decode_from_list(non_neg_integer(), list()) :: {:ok, OracleQuery.t()} | {:error, reason()}
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
