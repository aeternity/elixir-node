defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aeutil.Parser

  @type transaction_types :: SpendTx.t() | DataTx.t()

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
  def header(header, :serialize) do
    header
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn({key, value}, new_header) ->
      Map.put(new_header, Parser.to_string!(key), serialize_value(value))
    end)
  end

  def header(header, :deserialize) do
    Enum.reduce(header, %{}, fn({key, value}, new_header) ->
      Map.put(new_header, Parser.to_atom!(key), deserialize_value(value))
    end)
  end

  @spec tx(SignedTx.t(), :serialize | :deserialize) :: SignedTx.t()
  def tx(tx, :serialize) do
    data = DataTx.serialize(tx.data, :serialize)
    signature = hex_binary(tx.signature, :serialize)
    %{"data" => data, "signature" => signature}
  end

  def tx(tx, :deserialize) do
    tx_data = tx["data"]
    data = DataTx.serialize(tx_data, :deserialize)
    signature = hex_binary(tx["signature"], :deserialize)
    %SignedTx{data: data, signature: signature}
  end

  @spec hex_binary(binary(), :serialize | :deserialize) :: binary()
  def hex_binary(data, :serialize) when data != nil, do: Base.encode16(data)
  def hex_binary(data, :deserialize) when data != nil, do: Base.decode16!(data)
  def hex_binary(data, _),  do: nil

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
    case term do
      %Block{} ->
        Map.from_struct(%{term | header: Map.from_struct(term.header)})

      %SignedTx{} ->
        Map.from_struct(%{term | data: Map.from_struct(term.data)})

      %DataTx{} ->
        Map.from_struct(%{term | payload: Map.from_struct(term.payload)})

      %{__struct__: _} ->
        Map.from_struct(term)

      _ ->
        term
    end
    |> Msgpax.pack!(iodata: false)
  end

  def serialize_value(nil), do: nil

  def serialize_value(value) when is_list(value) do
    for elem <- value do
      serialize_value(elem)
    end
  end

  def serialize_value(value) when is_map(value) do
    value =
      case Map.has_key?(value, :__struct__) do
        true -> Map.from_struct(value)
        false -> value
      end

    Enum.reduce(value, %{},
      fn({key, val}, new_val)->
        Map.put(new_val, serialize_value(key), serialize_value(val))
      end)
  end

  def serialize_value(value) when is_binary(value) do
    hex_binary(value, :serialize)
  end

  def serialize_value(value) when is_atom(value) do
    Atom.to_string(value)
  end

  def serialize_value(value), do: value

  def deserialize_value(nil), do: nil

  def deserialize_value(value) when is_list(value) do
    for elem <- value do
      deserialize_value(elem)
    end
  end

  def deserialize_value(value) when is_map(value) do
    Enum.reduce(value, %{},
      fn({key, val}, new_value) ->
        Map.put(new_value, deserialize_value(key), deserialize_value(val))
      end)
  end

  def deserialize_value(value) when is_binary(value) do
    case Base.decode16(value, case: :upper) do
      {:ok, _} -> hex_binary(value, :deserialize)
      _-> Parser.to_atom!(value)
    end
  end

  def deserialize_value(value), do: value

end
