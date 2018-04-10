defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.OracleQueryTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Chainstate
  alias Aeutil.Parser
  alias Aecore.Structures.Account
  alias Aecore.Structures.SpendTx

  @type transaction_types :: SpendTx.t() | DataTx.t()

  @type hash_types :: :chainstate | :header | :txs

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
  @spec block(Block.t() | map(), :serialize | :deserialize) :: map | Block.t()
  def block(block, :serialize) do
    serialized_block = serialize_value(block)
    Map.put(serialized_block["header"], "transactions", serialized_block["txs"])
  end

  def block(block, :deserialize) do
    txs = Enum.map(block["transactions"], fn tx -> tx(tx, :deserialize) end)

    built_header =
      block
      |> Map.delete("transactions")
      |> deserialize_value()
      |> Header.new()

    Block.new(header: built_header, txs: txs)
  end

  @spec tx(map(), :serialize | :deserialize) :: SignedTx.t()
  def tx(tx, :serialize) do
    serialize_value(tx)
  end

  def tx(tx, :deserialize) do
    tx_data = tx["data"]

    data = DataTx.deserialize(tx_data)

    signature = base64_binary(tx["signature"], :deserialize)
    %SignedTx{data: data, signature: signature}
  end

  @spec account_state(Account.t() | :none | binary(), :serialize | :deserialize) ::
          binary() | :none | Account.t()
  def account_state(account_state, :serialize) do
    account_state
    |> serialize_value()
    |> Msgpax.pack!()
  end

  def account_state(:none, :deserialize), do: :none

  def account_state(encoded_account_state, :deserialize) do
    {:ok, account_state} = Msgpax.unpack(encoded_account_state)

    {:ok,
     account_state
     |> deserialize_value()
     |> Account.new()}
  end

  @spec hex_binary(binary(), :serialize | :deserialize) :: binary()
  def hex_binary(data, :serialize) when data != nil, do: Base.encode16(data)
  def hex_binary(data, :deserialize) when data != nil, do: Base.decode16!(data)
  def hex_binary(_, _), do: nil

  @spec base64_binary(binary(), :serialize | :deserialize) :: String.t() | binary()
  def base64_binary(data, :serialize) when data != nil, do: Base.encode64(data)
  def base64_binary(data, :deserialize) when data != nil, do: Base.decode64!(data)
  def base64_binary(_, _), do: nil

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
      acc = [serialize_value(head, :proof) | acc]
      merkle_proof(tail, acc)
    end
  end

  @spec pack_binary(term()) :: map()
  def pack_binary(term) do
    term
    |> remove_struct()
    |> Msgpax.pack!(iodata: false)
  end

  @doc """
  Loops through a structure are simplifies it. Removes all the strucutured maps
  """
  @spec remove_struct(list()) :: list()
  @spec remove_struct(map()) :: map()
  def remove_struct(term) when is_list(term) do
    for elem <- term, do: remove_struct(elem)
  end

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

  @doc """
  Initializing function to the recursive functionality of serializing a strucure
  """
  @spec serialize_value(any()) :: any()
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
      Map.put(new_val, serialize_value(key), serialize_value(val, key))
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

      :sender ->
        Account.base58c_encode(value)

      :receiver ->
        Account.base58c_encode(value)

      :oracle_address ->
        Account.base58c_encode(value)

      :query_id ->
        OracleQueryTx.base58c_encode(value)

      :signature ->
        base64_binary(value, :serialize)

      :proof ->
        base64_binary(value, :serialize)

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
  @spec deserialize_value(any()) :: any()
  def deserialize_value(value), do: deserialize_value(value, "")

  @doc """
  Loops recursively through a given serialized structure, converts the keys to atoms
  and decodes the encoded binary values
  """
  @spec deserialize_value(list()) :: list()
  @spec deserialize_value(map()) :: map()
  @spec deserialize_value(binary()) :: binary() | atom()
  def deserialize_value(nil, _), do: nil

  def deserialize_value(value, type) when is_list(value) do
    for elem <- value, do: deserialize_value(elem, type)
  end

  def deserialize_value(value, _) when is_map(value) do
    Enum.reduce(value, %{}, fn {key, val}, new_value ->
      case key do
        "pow" ->
          Map.put(new_value, :pow_evidence, deserialize_value(val, :pow_evidence))

        "state_hash" ->
          Map.put(new_value, :root_hash, deserialize_value(val, :root_hash))

        _ ->
          Map.put(new_value, Parser.to_atom!(key), deserialize_value(val, Parser.to_atom!(key)))
      end
    end)
  end

  def deserialize_value(value, type) when is_binary(value) do
    case type do
      :root_hash ->
        Chainstate.base58c_decode(value)

      :prev_hash ->
        Header.base58c_decode(value)

      :txs_hash ->
        SignedTx.base58c_decode_root(value)

      :sender ->
        Account.base58c_decode(value)

      :receiver ->
        Account.base58c_decode(value)

      :oracle_address ->
        Account.base58c_decode(value)

      :query_id ->
        OracleQueryTx.base58c_decode(value)

      :signature ->
        base64_binary(value, :deserialize)

      :proof ->
        base64_binary(value, :deserialize)

      _ ->
        Parser.to_atom!(value)
    end
  end

  def deserialize_value(value, _), do: value

  @spec serialize_txs_info_to_json(list(raw_data())) :: list(map())
  def serialize_txs_info_to_json(txs_info) when is_list(txs_info) do
    serialize_txs_info_to_json(txs_info, [])
  end

  defp serialize_txs_info_to_json([h | t], acc) do
    json_response_struct = %{
      tx: %{
        sender: Account.base58c_encode(h.sender),
        recipient: Account.base58c_encode(h.payload.receiver),
        amount: h.payload.amount,
        fee: h.fee,
        nonce: h.nonce,
        vsn: h.payload.version
      },
      block_height: h.block_height,
      block_hash: Header.base58c_encode(h.block_hash),
      hash: SignedTx.base58c_encode_root(h.txs_hash),
      signatures: [base64_binary(h.signature, :serialize)]
    }

    acc = acc ++ [json_response_struct]
    serialize_txs_info_to_json(t, acc)
  end

  defp serialize_txs_info_to_json([], acc) do
    acc
  end
end
