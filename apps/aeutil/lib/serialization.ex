defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Chain.Header
  alias Aecore.Tx.SignedTx
  alias Aecore.Naming.NameCommitment
  alias Aecore.Naming.Name
  alias Aecore.Chain.Chainstate
  alias Aeutil.Parser
  alias Aecore.Account.Account
  alias Aecore.Tx.DataTx
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aeutil.TypeToTag

  require Logger

  @type value :: list() | map() | atom() | binary()

  @type raw_data :: %{
          block_hash: binary(),
          block_height: non_neg_integer(),
          fee: non_neg_integer(),
          nonce: non_neg_integer(),
          payload: SpendTx.t(),
          sender: binary() | nil,
          signature: binary() | nil,
          txs_hash: binary(),
          type: atom()
        }

  @spec hex_binary(binary(), :serialize | :deserialize) :: binary()
  def hex_binary(data, :serialize) when data != nil, do: Base.encode16(data)
  def hex_binary(data, :deserialize) when data != nil, do: Base.decode16!(data)
  def hex_binary(_, _), do: nil

  @spec base64_binary(binary(), :serialize | :deserialize) :: String.t() | binary()
  def base64_binary(data, :serialize) when data != nil, do: Base.encode64(data)
  def base64_binary(data, :deserialize) when data != nil, do: Base.decode64!(data)
  def base64_binary(_, _), do: nil

  @doc """
  Loops through a structure are simplifies it. Removes all the strucutured maps
  """
  @spec remove_struct(list()) :: list()
  def remove_struct(term) when is_list(term) do
    for elem <- term, do: remove_struct(elem)
  end

  @spec remove_struct(map()) :: map()
  def remove_struct(term) when is_map(term) do
    if Map.has_key?(term, :__struct__) do
      term
      |> Map.from_struct()
      |> Enum.reduce(%{}, fn {key, value}, term_acc ->
        Map.put(term_acc, key, remove_struct(value))
      end)
    else
      term
    end
  end

  def remove_struct(term), do: term

  def cache_key_encode(key, expires) do
    :sext.encode({expires, key})
  end

  def cache_key_decode(key) do
    :sext.decode(key)
  end

  @doc """
  Initializing function to the recursive functionality of serializing a strucure
  """
  @spec serialize_value(value()) :: value()
  def serialize_value(value), do: serialize_value(value, "")

  @doc """
  Loops recursively through a given structure. If it goes into a map
  the keys are converted to string and each binary value
  is encoded if necessary. (depends on the key)
  """
  @spec serialize_value(list(), atom()) :: list()
  @spec serialize_value(map(), atom()) :: map()
  @spec serialize_value(binary(), atom() | String.t()) :: binary()
  def serialize_value(nil, _), do: nil

  def serialize_value(value, type) when is_list(value) do
    for elem <- value, do: serialize_value(elem, type)
  end

  def serialize_value(value, _type) when is_map(value) do
    value
    |> remove_struct()
    |> Enum.reduce(%{}, fn {key, val}, new_val ->
      case key do
        :receiver -> Map.put(new_val, serialize_value(key), serialize_value(val.value, key))
        _ -> Map.put(new_val, serialize_value(key), serialize_value(val, key))
      end
    end)
  end

  def serialize_value(value, type) when is_binary(value) do
    case type do
      :root_hash ->
        Chainstate.base58c_encode(value)

      :prev_hash ->
        Header.base58c_encode(value)

      :txs_hash ->
        SignedTx.base58c_encode_root(value)

      :miner ->
        Account.base58c_encode(value)

      :sender ->
        Account.base58c_encode(value)

      :senders ->
        Account.base58c_encode(value)

      :receiver ->
        Account.base58c_encode(value)

      :target ->
        Account.base58c_encode(value)

      :oracle_address ->
        Account.base58c_encode(value)

      :query_id ->
        OracleQueryTx.base58c_encode(value)

      :signature ->
        SignedTx.base58c_encode_signature(value)

      :signatures ->
        SignedTx.base58c_encode_signature(value)

      :proof ->
        base64_binary(value, :serialize)

      :commitment ->
        NameCommitment.base58c_encode_commitment(value)

      :name_salt ->
        base64_binary(value, :serialize)

      :hash ->
        Name.base58c_encode_hash(value)

      :value ->
        Account.base58c_encode(value)

      _ ->
        value
    end
  end

  def serialize_value(value, _) when is_atom(value) do
    case value do
      :pow_evidence -> "pow"
      :root_hash -> "state_hash"
      _ -> Atom.to_string(value)
    end
  end

  def serialize_value(value, _), do: value

  @doc """
  Initializing function to the recursive functionality of deserializing a strucure
  """
  @spec deserialize_value(value()) :: value()
  def deserialize_value(value), do: deserialize_value(value, :other)

  @doc """
  Loops recursively through a given serialized structure, converts the keys to atoms
  and decodes the encoded binary values
  """
  @spec deserialize_value(nil, atom()) :: nil
  def deserialize_value(nil, _), do: nil

  @spec deserialize_value(list(), atom()) :: list()
  def deserialize_value(value, type) when is_list(value) do
    for elem <- value, do: deserialize_value(elem, type)
  end

  @spec deserialize_value(map(), atom()) :: map()
  def deserialize_value(value, _) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, val}, new_value ->
      case key do
        "pow" ->
          Map.put(new_value, :pow_evidence, deserialize_value(val, :pow_evidence))

        "state_hash" ->
          Map.put(new_value, :root_hash, deserialize_value(val, :root_hash))

        _ ->
          Map.put(new_value, Parser.to_atom(key), deserialize_value(val, Parser.to_atom(key)))
      end
    end)
  end

  @spec deserialize_value(binary(), atom()) :: binary() | atom()
  def deserialize_value(value, type) when is_binary(value) do
    case type do
      :root_hash ->
        Chainstate.base58c_decode(value)

      :prev_hash ->
        Header.base58c_decode(value)

      :txs_hash ->
        SignedTx.base58c_decode_root(value)

      :senders ->
        Account.base58c_decode(value)

      :sender ->
        Account.base58c_decode(value)

      :miner ->
        Account.base58c_decode(value)

      :receiver ->
        Account.base58c_decode(value)

      :oracle_address ->
        Account.base58c_decode(value)

      :query_id ->
        OracleQueryTx.base58c_decode(value)

      :target ->
        Account.base58c_decode(value)

      :signature ->
        SignedTx.base58c_decode_signature(value)

      :signatures ->
        SignedTx.base58c_decode_signature(value)

      :proof ->
        base64_binary(value, :deserialize)

      :commitment ->
        NameCommitment.base58c_decode_commitment(value)

      :name_salt ->
        base64_binary(value, :deserialize)

      :hash ->
        Name.base58c_decode_hash(value)

      :value ->
        Account.base58c_decode(value)

      :name ->
        value

      :payload ->
        value

      :query_data ->
        value

      _ ->
        Parser.to_atom(value)
    end
  end

  def deserialize_value(value, _), do: value

  @spec serialize_txs_info_to_json(list(raw_data())) :: list(map())
  def serialize_txs_info_to_json(txs_info) when is_list(txs_info) do
    serialize_txs_info_to_json(txs_info, [])
  end

  def serialize_term(term), do: :erlang.term_to_binary(term)
  def deserialize_term(:none), do: :none
  def deserialize_term({:ok, binary}), do: deserialize_term(binary)
  def deserialize_term(binary), do: {:ok, :erlang.binary_to_term(binary)}

  defp serialize_txs_info_to_json([h | t], acc) do
    tx = DataTx.init(h.type, h.payload, h.senders, h.fee, h.nonce, h.ttl)
    tx_hash = SignedTx.hash_tx(tx)

    senders_list =
      for sender <- h.senders do
        Account.base58c_encode(sender)
      end

    json_response_struct = %{
      tx: %{
        sender: senders_list,
        recipient: Account.base58c_encode(h.payload.receiver),
        amount: h.payload.amount,
        fee: h.fee,
        nonce: h.nonce,
        vsn: h.payload.version
      },
      block_height: h.block_height,
      block_hash: Header.base58c_encode(h.block_hash),
      hash: DataTx.base58c_encode(tx_hash),
      signatures:
        for sig <- h.signatures do
          SignedTx.base58c_encode_signature(sig)
        end
    }

    acc = [json_response_struct | acc]
    serialize_txs_info_to_json(t, acc)
  end

  defp serialize_txs_info_to_json([], acc) do
    Enum.reverse(acc)
  end

  @spec rlp_encode(map()) :: binary | {:error, String.t()}
  def rlp_encode(structure) when is_map(structure) do
    with {:ok, tag} <- TypeToTag.type_to_tag(structure.__struct__) do
      ExRLP.encode([tag | structure.__struct__.encode_to_list(structure)])
    else
      error ->
        error
    end
  end

  def rlp_encode(data) do
    {:error, "#{__MODULE__}: Illegal serialization attempt: #{inspect(data)}"}
  end

  @spec rlp_decode_anything(binary()) :: term() | {:error, binary()}
  def rlp_decode_anything(binary) do
    rlp_decode(binary)
  end

  @spec rlp_decode_only(binary(), atom()) :: term() | {:error, binary()}
  def rlp_decode_only(binary, type) do
    rlp_decode(binary, type)
  end

  @spec rlp_decode(binary(), atom()) :: term() | {:error, binary()}
  defp rlp_decode(binary, type \\ :any) when is_binary(binary) do
    result =
      try do
        ExRLP.decode(binary)
      rescue
        e ->
          {:error, "#{__MODULE__}: rlp_decode: IIllegal serialization: #{Exception.message(e)}"}
      end

    case result do
      [tag_bin, ver_bin | rest_data] ->
        case TypeToTag.tag_to_type(:binary.decode_unsigned(tag_bin)) do
          {:ok, actual_type} ->
            version = :binary.decode_unsigned(ver_bin)

            if actual_type == type || type == :any do
              actual_type.decode_from_list(version, rest_data)
            else
              {:error,
               "#{__MODULE__}: rlp_decode: Invalid type: #{actual_type}, but wanted: #{type}"}
            end

          {:error, _} = error ->
            error
        end

      [] ->
        {:error, "#{__MODULE__}: rlp_decode: Empty encoding"}

      {:error, _} = error ->
        error
    end
  end

  def encode_ttl_type(%{ttl: _ttl, type: :absolute}), do: <<1>>
  def encode_ttl_type(%{ttl: _ttl, type: :relative}), do: <<0>>
  def decode_ttl_type(<<1>>), do: :absolute
  def decode_ttl_type(<<0>>), do: :relative
end
