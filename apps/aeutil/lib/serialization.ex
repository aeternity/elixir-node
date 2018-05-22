defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Oracle.Tx.OracleExtendTx
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Oracle.Tx.OracleRegistrationTx
  alias Aecore.Oracle.Tx.OracleResponseTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Naming.Naming
  alias Aecore.Chain.Chainstate
  alias Aeutil.Parser
  alias Aecore.Account.Account
  alias Aecore.Tx.DataTx
  alias Aecore.Oracle.Oracle
  alias Aecore.Naming.Tx.NamePreClaimTx
  alias Aecore.Naming.Tx.NameClaimTx
  alias Aecore.Naming.Tx.NameUpdateTx
  alias Aecore.Naming.Tx.NameTransferTx
  alias Aecore.Naming.Tx.NameRevokeTx
  alias Aecore.Account.Tx.CoinbaseTx

  require Logger

  @type transaction_types :: SpendTx.t() | DataTx.t()

  @type hash_types :: :chainstate | :header | :txs

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
  @spec block(Block.t() | map(), :serialize | :deserialize) :: map() | Block.t()
  def block(block, :serialize) do
    serialized_header = serialize_value(block.header)
    serialized_txs = Enum.map(block.txs, fn tx -> SignedTx.serialize(tx) end)

    Map.put(serialized_header, "transactions", serialized_txs)
  end

  def block(block, :deserialize) do
    txs = Enum.map(block["transactions"], fn tx -> SignedTx.deserialize(tx) end)

    built_header =
      block
      |> Map.delete("transactions")
      |> deserialize_value()
      |> Header.new()

    Block.new(header: built_header, txs: txs)
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

  @spec pack_binary(term()) :: binary()
  def pack_binary(term) do
    term
    |> remove_struct()
    |> Msgpax.pack!(iodata: false)
  end

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
        base64_binary(value, :serialize)

      :signatures ->
        base64_binary(value, :deserialize)

      :proof ->
        base64_binary(value, :serialize)

      :commitment ->
        Naming.base58c_encode_commitment(value)

      :name_salt ->
        base64_binary(value, :serialize)

      :hash ->
        Naming.base58c_encode_hash(value)

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

      :receiver ->
        Account.base58c_decode(value)

      :oracle_address ->
        Account.base58c_decode(value)

      :query_id ->
        OracleQueryTx.base58c_decode(value)

      :target ->
        Account.base58c_decode(value)

      :signature ->
        base64_binary(value, :deserialize)

      :signatures ->
        base64_binary(value, :deserialize)

      :proof ->
        base64_binary(value, :deserialize)

      :commitment ->
        Naming.base58c_decode_commitment(value)

      :name_salt ->
        base64_binary(value, :deserialize)

      :hash ->
        Naming.base58c_decode_hash(value)

      :name ->
        value

      :payload ->
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

  defp serialize_txs_info_to_json([h | t], acc) do
    tx = DataTx.init(h.type, h.payload, h.senders, h.fee, h.nonce)
    tx_hash = SignedTx.hash_tx(%SignedTx{data: tx, signatures: []})

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

  @spec rlp_encode(Account.t() | DataTx.t() | map(), :tx | :ac | :ro | :io | :signedtx) ::
          binary | {:error, String.t()}
  def rlp_encode(%DataTx{} = term, :tx) do
    with {:ok, tag} <- type_to_tag(term.type),
         {:ok, vsn} <- get_version(term.type),
         data <- term.__struct__.rlp_encode(tag, vsn, term) do
      data
    else
      error -> {:error, "#{__MODULE__} : Invalid DataTx serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%Account{} = term, :as) when is_map(term) do
    with {:ok, tag} <- type_to_tag(term.__struct__),
         {:ok, vsn} <- get_version(term.__struct__),
         data <- term.__struct__.rlp_encode(tag, vsn, term) do
      data
    else
      error ->
        {:error, "#{__MODULE__} : Invalid Account state serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%{} = term, :io) do
    with {:ok, tag} <- type_to_tag(OracleQuery),
         {:ok, vsn} <- get_version(OracleQuery),
         data <- Oracle.rlp_encode(tag, vsn, term, :interaction_object) do
      data
    else
      error ->
        {:error,
         "#{__MODULE__} : Invalid interaction object state serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%{} = term, :ro) when is_map(term) do
    with {:ok, tag} <- type_to_tag(Oracle),
         {:ok, vsn} <- get_version(Oracle),
         data <- Oracle.rlp_encode(tag, vsn, term, :registered_oracle) do
      data
    else
      error ->
        {:error,
         "#{__MODULE__} : Invalid registered oracle state serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%{} = term, :ns) when is_map(term) do
    with {:ok, tag} <- type_to_tag(Name),
         {:ok, vsn} <- get_version(Name),
         data <- Naming.rlp_encode(tag, vsn, term, :name) do
      data
    else
      error -> {:error, "#{__MODULE__} : Invalid naming state serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%{} = term, :nc) when is_map(term) do
    with {:ok, tag} <- type_to_tag(NameCommitment),
         {:ok, vsn} <- get_version(NameCommitment),
         data <- Naming.rlp_encode(tag, vsn, term, :name_commitment) do
      data
    else
      error ->
        {:error, "#{__MODULE__} : Invalid name commitment state serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%Block{} = term, :block) do
    with {:ok, tag} <- type_to_tag(term.__struct__),
         {:ok, vsn} <- get_version(term.__struct__),
         data <- term.__struct__.rlp_encode(tag, vsn, term) do
      data
    else
      error ->
        {:error,
         "#{__MODULE__} : Invalid interaction object states serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%SignedTx{} = term, :signedtx) do
    with {:ok, tag} <- type_to_tag(term.__struct__),
         {:ok, vsn} <- get_version(term.__struct__),
         data <- term.__struct__.rlp_encode(tag, vsn, term) do
      data
    else
      error -> {:error, "#{__MODULE__} : Invalid Tx serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(error) do
    {:error, "#{__MODULE__} : Illegal serialization attempt: #{inspect(error)}"}
  end

  def rlp_decode(binary) when is_binary(binary) do
    [tag_bin, ver_bin | rest_data] = ExRLP.decode(binary)
    tag = transform_item(tag_bin, :int)
    ver = transform_item(ver_bin, :int)
    rlp_decode(tag_to_type(tag), ver, rest_data)
  end

  def rlp_decode(data) do
    {:error, "#{__MODULE__}: Illegal deserialization: #{inspect(data)}"}
  end

  defp rlp_decode(Block, _vsn, block_data) do
    Block.rlp_decode(block_data)
  end

  defp rlp_decode(Name, _vsn, name_data) do
    Naming.rlp_decode(name_data, :name)
  end

  defp rlp_decode(NameCommitment, _vsn, name_commitment) do
    Naming.rlp_decode(name_commitment, :name_commitment)
  end

  defp rlp_decode(Oracle, _vsn, reg_orc) do
    Oracle.rlp_decode(reg_orc, :registered_oracle)
  end

  defp rlp_decode(OracleQuery, _vsn, interaction_object) do
    Oracle.rlp_decode(interaction_object, :interaction_object)
  end

  defp rlp_decode(Account, _vsn, account_state) do
    Account.rlp_decode(account_state)
  end

  defp rlp_decode(SignedTx, _vsn, signedtx) do
    SignedTx.rlp_decode(signedtx)
  end

  defp rlp_decode(payload, _vsn, datatx) do
    DataTx.rlp_decode(payload, datatx)
  end

  # Should be changed after some adjustments in oracle structures
  def transform_item(item) do
    Poison.encode!(item)
  end

  def transform_item(item, type) do
    case type do
      :int -> :binary.decode_unsigned(item)
      :binary -> Poison.decode!(item)
    end
  end

  def encode_ttl_type(%{ttl: _ttl, type: :absolute}), do: 1
  def encode_ttl_type(%{ttl: _ttl, type: :relative}), do: 0
  def decode_ttl_type(1), do: :absolute
  def decode_ttl_type(0), do: :relative

  @spec type_to_tag(atom()) :: non_neg_integer() | {:error, String.t()}
  def type_to_tag(Account), do: {:ok, 10}
  def type_to_tag(SignedTx), do: {:ok, 11}
  def type_to_tag(SpendTx), do: {:ok, 12}
  def type_to_tag(CoinbaseTx), do: {:ok, 13}
  def type_to_tag(OracleRegistrationTx), do: {:ok, 22}
  def type_to_tag(OracleQueryTx), do: {:ok, 23}
  def type_to_tag(OracleResponseTx), do: {:ok, 24}
  def type_to_tag(OracleExtendTx), do: {:ok, 25}
  def type_to_tag(Name), do: {:ok, 30}
  def type_to_tag(NameCommitment), do: {:ok, 31}
  def type_to_tag(NameClaimTx), do: {:ok, 32}
  def type_to_tag(NamePreClaimTx), do: {:ok, 33}
  def type_to_tag(NameUpdateTx), do: {:ok, 34}
  def type_to_tag(NameRevokeTx), do: {:ok, 35}
  def type_to_tag(NameTransferTx), do: {:ok, 36}
  def type_to_tag(Oracle), do: {:ok, 20}
  def type_to_tag(OracleQuery), do: {:ok, 21}
  def type_to_tag(Block), do: {:ok, 100}
  def type_to_tag(type), do: {:error, "#{__MODULE__} : Unknown TX Type: #{type}"}

  @spec tag_to_type(non_neg_integer()) :: atom() | {:error, String.t()}
  def tag_to_type(10), do: Account
  def tag_to_type(12), do: SpendTx
  def tag_to_type(13), do: CoinbaseTx
  def tag_to_type(22), do: OracleRegistrationTx
  def tag_to_type(23), do: OracleQueryTx
  def tag_to_type(24), do: OracleResponseTx
  def tag_to_type(25), do: OracleExtendTx
  def tag_to_type(30), do: Name
  def tag_to_type(31), do: NameCommitmentTx
  def tag_to_type(32), do: NameClaimTx
  def tag_to_type(33), do: NamePreClaimTx
  def tag_to_type(34), do: NameUpdateTx
  def tag_to_type(35), do: NameRevokeTx
  def tag_to_type(36), do: NameTransferTx
  def tag_to_type(20), do: Oracle
  def tag_to_type(21), do: OracleQuery
  def tag_to_type(11), do: SignedTx
  def tag_to_type(100), do: Block
  def tag_to_type(tag), do: {:error, "#{__MODULE__} : Unknown TX Tag: #{inspect(tag)}"}

  @spec get_version(atom()) :: non_neg_integer() | {:error, String.t()}
  def get_version(SpendTx), do: {:ok, 1}
  def get_version(CoinbaseTx), do: {:ok, 1}
  def get_version(OracleRegistrationTx), do: {:ok, 1}
  def get_version(OracleQueryTx), do: {:ok, 1}
  def get_version(OracleResponseTx), do: {:ok, 1}
  def get_version(OracleExtendTx), do: {:ok, 1}
  def get_version(NameName), do: {:ok, 1}
  def get_version(NameCommitment), do: {:ok, 1}
  def get_version(NameClaimTx), do: {:ok, 1}
  def get_version(NamePreClaimTx), do: {:ok, 1}
  def get_version(NameUpdateTx), do: {:ok, 1}
  def get_version(NameRevokeTx), do: {:ok, 1}
  def get_version(NameTransferTx), do: {:ok, 1}
  def get_version(Account), do: {:ok, 1}
  def get_version(Oracle), do: {:ok, 1}
  def get_version(OracleQuery), do: {:ok, 1}
  def get_version(SignedTx), do: {:ok, 1}
  def get_version(ver), do: {:error, "#{__MODULE__} : Unknown Struct version: #{inspect(ver)}"}
end
