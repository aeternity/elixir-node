defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias __MODULE__
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.ChainState
  alias Aeutil.Parser
  alias Aeutil.Bits

  @type transaction_types :: SpendTx.t() | DataTx.t()

  @type hash_types :: :chainstate | :header | :txs

  @spec block(Block.t(), :serialize | :deserialize) :: Block.t()
  def block(block, :serialize) do
    header = header(block.header, :serialize)
    txs = Enum.map(block.txs, fn(tx) -> tx(tx, :serialize) end)
    %{"header" => header, "txs" => txs}
  end

  def block(block, :deserialize) do
    built_header =
      block["header"]
      |> header(:deserialize)
      |> Header.new()

    txs = Enum.map(block["txs"], fn(tx) -> tx(tx, :deserialize) end)
    Block.new(header: built_header, txs: txs)
  end

  @spec header(Header.t(), :serialize | :deserialize) :: Header.t()
  def header(header, :serialize), do: serialize_value(header)
  def header(header, :deserialize), do: deserialize_value(header)

  @spec tx(SignedTx.t(), :serialize | :deserialize) :: SignedTx.t()
  def tx(tx, :serialize) do
    data = DataTx.serialize(tx.data, :serialize)
    signature = base64_binary(tx.signature, :serialize)
    %{"data" => data, "signature" => signature}
  end

  def tx(tx, :deserialize) do
    tx_data = tx["data"]
    data = DataTx.serialize(tx_data, :deserialize)
    signature = base64_binary(tx["signature"], :deserialize)
    %SignedTx{data: data, signature: signature}
  end

  @spec hex_binary(binary(), :serialize | :deserialize) :: binary()
  def hex_binary(data, :serialize) when data != nil, do: Base.encode16(data)
  def hex_binary(data, :deserialize) when data != nil, do: Base.decode16!(data)
  def hex_binary(data, _),  do: nil

  @spec base64_binary(binary(), :serialize | :deserialize) :: String.t() | binary()
  def base64_binary(data, direction) do
    if data != nil do
      case(direction) do
        :serialize ->
          Base.encode64(data)

        :deserialize ->
          Base.decode64!(data)
      end
    else
      nil
    end
  end

  def merkle_proof(proof, acc) when is_tuple(proof) do
    proof
    |> Tuple.to_list()
    |> merkle_proof(acc)
  end

  def merkle_proof([], acc), do: acc

  def merkle_proof([head | tail], acc) do
    if is_tuple(head) do
      merkle_proof(Tuple.to_list(head), acc)
    else
      acc = [hex_binary(head, :serialize)| acc]
      merkle_proof(tail, acc)
    end
  end

  @spec pack_binary(term()) :: map()
  def pack_binary(term) do
    pb = pack_binary(term, "")
    Msgpax.pack!(pb, iodata: false)
  end

  def pack_binary(term) when is_list(term) do
    for elem <- term, do: pack_binary(term, "")
  end

  def pack_binary(term, _) when is_map(term) do
    if Map.has_key?(term, :__struct__) do
      term
      |> Map.from_struct()
      |> Enum.reduce(%{},
      fn({key, value}, term_acc) ->
        Map.put(term_acc, key, pack_binary(value, ""))
      end)
    else
      term
    end
  end

  def pack_binary(term, _), do: term

  def serialize_value(value), do: serialize_value(value, "")

  def serialize_value(nil, _), do: nil

  def serialize_value(value, type) when is_list(value) do
    for elem <- value do
      serialize_value(elem, type)
    end
  end

  def serialize_value(value, type) when is_map(value) do
    value =
      case Map.has_key?(value, :__struct__) do
        true -> Map.from_struct(value)
        false -> value
      end

    Enum.reduce(value, %{}, fn({key, val}, new_val)->
      Map.put(new_val, serialize_value(key), serialize_value(val, key))
    end)
  end

  def serialize_value(value, type) when is_binary(value) do
    case type do
      :prev_hash ->
        Header.bech32_encode(value)

      :txs_hash ->
        SignedTx.bech32_encode_root(value)

      :chain_state_hash ->
        ChainState.bech32_encode(value)

      _ ->
        Aewallet.Encoding.encode(value, :ae)
    end
  end

  def serialize_value(value, _) when is_atom(value) do
    Atom.to_string(value)
  end

  def serialize_value(value, _), do: value

  def deserialize_value(nil), do: nil

  def deserialize_value(value) when is_list(value) do
    for elem <- value, do: deserialize_value(elem)
  end

  def deserialize_value(value) when is_map(value) do
    Enum.reduce(value, %{}, fn({key, val}, new_value) ->
        Map.put(new_value, Parser.to_atom!(key), deserialize_value(val))
      end)
  end

  def deserialize_value(value) when is_binary(value) do
    case Bits.bech32_decode(value) do
      {:error, _reason} -> Parser.to_atom!(value)
      value -> value
    end
  end

  def deserialize_value(value), do: value

end
