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
  alias Aecore.Channel.Tx.ChannelCreateTx
  alias Aecore.Channel.Tx.ChannelCloseMutalTx
  alias Aecore.Channel.Tx.ChannelCloseSoloTx
  alias Aecore.Channel.Tx.ChannelSlashTx
  alias Aecore.Channel.Tx.ChannelSettleTx
  alias Aecore.Channel.ChannelStateOnChain

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

  @spec block(Block.t(), :serialize) :: map()
  def block(%Block{} = block, :serialize) do
    serialized_header = serialize_value(block.header)
    serialized_txs = Enum.map(block.txs, fn tx -> SignedTx.serialize(tx) end)

    Map.put(serialized_header, "transactions", serialized_txs)
  end

  @spec block(map(), :deserialize) :: Block.t()
  def block(%{} = block, :deserialize) do
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
        base64_binary(value, :serialize)

      :signatures ->
        base64_binary(value, :serialize)

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

  def serialize_term(term), do: :erlang.term_to_binary(term)
  def deserialize_term(:none), do: :none
  def deserialize_term({:ok, binary}), do: deserialize_term(binary)
  def deserialize_term(binary), do: {:ok, :erlang.binary_to_term(binary)}

  defp serialize_txs_info_to_json([h | t], acc) do
    tx = DataTx.init(h.type, h.payload, h.senders, h.fee, h.nonce, h.ttl)
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

  @spec rlp_encode(
          Account.t() | DataTx.t() | map(),
          :account_state
          | :registered_oracle
          | :interaction_object
          | :naming_state
          | :name_commitment
          | :channel_onchain
          | :block
        ) :: binary | {:error, String.t()}

  def rlp_encode(%Account{} = term, :account_state) when is_map(term) do
    with {:ok, tag} <- type_to_tag(term.__struct__),
         {:ok, version} <- get_version(term.__struct__),
         data <- term.__struct__.rlp_encode(tag, version, term) do
      data
    else
      error ->
        {:error, "#{__MODULE__} : Invalid Account state serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%{} = term, :oracle_query) do
    with {:ok, tag} <- type_to_tag(OracleQuery),
         {:ok, version} <- get_version(OracleQuery),
         data <- Oracle.rlp_encode(tag, version, term, :oracle_query) do
      data
    else
      error ->
        {:error,
         "#{__MODULE__} : Invalid Interaction Object state serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%{} = term, :oracle) when is_map(term) do
    with {:ok, tag} <- type_to_tag(Oracle),
         {:ok, version} <- get_version(Oracle),
         data <- Oracle.rlp_encode(tag, version, term, :oracle) do
      data
    else
      error ->
        {:error,
         "#{__MODULE__} : Invalid Registered Oracle state serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%{} = term, :naming_state) when is_map(term) do
    with {:ok, tag} <- type_to_tag(Name),
         {:ok, version} <- get_version(Name),
         data <- Naming.rlp_encode(tag, version, term, :naming_state) do
      data
    else
      error -> {:error, "#{__MODULE__} : Invalid Naming State serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%{} = term, :name_commitment) when is_map(term) do
    with {:ok, tag} <- type_to_tag(NameCommitment),
         {:ok, version} <- get_version(NameCommitment),
         data <- Naming.rlp_encode(tag, version, term, :name_commitment) do
      data
    else
      error ->
        {:error, "#{__MODULE__} : Invalid Name Commitment State serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%ChannelStateOnChain{} = term, :channel_onchain) when is_map(term) do
    with {:ok, tag} <- type_to_tag(term.__struct__),
         {:ok, version} <- get_version(term.__struct__),
         data <- term.__struct__.rlp_encode(tag, version, term) do
      data
    else
      error ->
        {:error,
         "#{__MODULE__} : Invalid Channel on-chain state serialization: #{inspect(error)}"}
    end
  end

  def rlp_encode(%Block{} = term, :block) do
    with {:ok, tag} <- type_to_tag(term.__struct__),
         data <- term.__struct__.rlp_encode(tag, 1, term) do
      data
    else
      error ->
        {:error, "#{__MODULE__} : Invalid Block structure serialization : #{inspect(error)}"}
    end
  end

  def rlp_encode(structure) when is_map(structure) do
    with {:ok, tag} <- type_to_tag(structure.__struct__) do
      ExRLP.encode([tag | structure.__struct__.encode_to_list(structure)])
    else
      error ->
        error
    end
  end

  def rlp_encode(data) do
    {:error, "#{__MODULE__}: Illegal serialization attempt: #{inspect(error)}"}
  end

  defp rlp_decode(Block, _version, block_data) do
    Block.rlp_decode(block_data)
  end

  defp rlp_decode(Name, _version, name_data) do
    Naming.rlp_decode(name_data, :name)
  end

  defp rlp_decode(NameCommitment, _version, name_commitment) do
    Naming.rlp_decode(name_commitment, :name_commitment)
  end

  defp rlp_decode(Oracle, _version, oracle) do
    Oracle.rlp_decode(oracle, :oracle)
  end

  defp rlp_decode(OracleQuery, _version, oracle_query) do
    Oracle.rlp_decode(oracle_query, :oracle_query)
  end

  defp rlp_decode(Account, _version, account_state) do
    Account.rlp_decode(account_state)
  end

  defp rlp_decode(SignedTx, _version, signedtx) do
    SignedTx.rlp_decode(signedtx)
  end

  defp rlp_decode(ChannelStateOnChain, _version, channel_state_on_chain) do
    ChannelStateOnChain.rlp_decode(channel_state_on_chain)
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
      [tag_bin | rest_data] ->
        actual_type =
          tag_bin
          |> Serialization.transform_item(:int)
          |> tag_to_type

        if actual_type == type || type == :any do
          actual_type.decode_from_list(rest_data)
        else
          {:error, "#{__MODULE__}: rlp_decode: Invalid type: #{actual_type}"}
        end

      [] ->
        {:error, "#{__MODULE__}: rlp_decode: IEmpty encoding"}

      {:error, _} = error ->
        error
    end
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

  @spec header_to_binary(Header.t()) :: binary
  def header_to_binary(%Header{} = header) do
    header_prev_hash_size = Application.get_env(:aecore, :bytes_size)[:header_hash]
    header_txs_hash_size = Application.get_env(:aecore, :bytes_size)[:txs_hash]
    header_root_hash_size = Application.get_env(:aecore, :bytes_size)[:root_hash]
    pow_evidence_size = Application.get_env(:aecore, :bytes_size)[:pow_total_size]

    pow_to_binary =
      if header.pow_evidence != :no_value do
        pow_to_binary(header.pow_evidence)
      else
        pow_to_binary(List.duplicate(0, 42))
      end

    # Application.get_env(:aecore, :aewallet)[:pub_key_size] should be used instead of hardcoded value
    miner_pubkey_size = 33

    <<
      header.version::64,
      header.height::64,
      header.prev_hash::binary-size(header_prev_hash_size),
      header.txs_hash::binary-size(header_txs_hash_size),
      header.root_hash::binary-size(header_root_hash_size),
      header.target::64,
      pow_to_binary::binary-size(pow_evidence_size),
      header.nonce::64,
      header.time::64,
      # pubkey should be adjusted to 32 bytes.
      header.miner::binary-size(miner_pubkey_size)
    >>
  end

  def header_to_binary(_) do
    {:error, "#{__MODULE__} : Illegal header structure serialization"}
  end

  @spec binary_to_header(binary()) :: Header.t() | {:error, String.t()}
  def binary_to_header(binary) when is_binary(binary) do
    # Application.get_env(:aecore, :aewallet)[:pub_key_size]
    miner_pubkey_size = 33
    header_prev_hash_size = Application.get_env(:aecore, :bytes_size)[:header_hash]
    header_txs_hash_size = Application.get_env(:aecore, :bytes_size)[:txs_hash]
    header_root_hash_size = Application.get_env(:aecore, :bytes_size)[:root_hash]
    pow_evidence_size = Application.get_env(:aecore, :bytes_size)[:pow_total_size]

    <<
      version::64,
      height::64,
      prev_hash::binary-size(header_prev_hash_size),
      txs_hash::binary-size(header_txs_hash_size),
      root_hash::binary-size(header_root_hash_size),
      target::64,
      pow_evidence_bin::binary-size(pow_evidence_size),
      nonce::64,
      # pubkey should be adjusted to 32 bytes.
      time::64,
      miner::binary-size(miner_pubkey_size)
    >> = binary

    pow_evidence = binary_to_pow(pow_evidence_bin)

    %Header{
      height: height,
      nonce: nonce,
      pow_evidence: pow_evidence,
      prev_hash: prev_hash,
      root_hash: root_hash,
      target: target,
      time: time,
      txs_hash: txs_hash,
      version: version,
      miner: miner
    }
  end

  def binary_to_header(_) do
    {:error, "#{__MODULE__} : Illegal header to binary serialization"}
  end

  # Optional function-workaroud:
  # As we have differences in value types in some fields,
  # which means that we encode these fields different apart from what Epoch does,
  # we need to recognize the origins of this value.
  # My proposal is (until the problem is solved) to add
  # specific prefix to the data before encodings, for example, "$æx"
  # this prefix will allow us to know, how the data should be handled.
  # But it also makes problems and inconsistency in Epoch, because they dont handle these prefixes.
  @spec decode_format(binary()) :: binary()
  defp decode_format(<<"$æx", binary::binary>>) do
    Serialization.transform_item(binary, :binary)
  end

  defp decode_format(binary) when is_binary(binary) do
    binary
  end

  @spec serialize_pow(binary(), binary()) :: binary() | {:error, String.t()}
  defp serialize_pow(pow, acc) when pow != <<>> do
    <<elem::binary-size(4), rest::binary>> = pow
    serialize_pow(rest, acc <> elem)
  end

  defp serialize_pow(<<>>, acc) do
    acc
  end

  @spec pow_to_binary(list()) :: binary() | list() | {:error, String.t()}
  def pow_to_binary(pow) do
    if is_list(pow) and Enum.count(pow) == 42 do
      list_of_pows =
        for evidence <- pow, into: <<>> do
          <<evidence::32>>
        end

      serialize_pow(list_of_pows, <<>>)
    else
      List.duplicate(0, 42)
    end
  end

  @spec binary_to_pow(binary()) :: list() | {:error, atom()}
  def binary_to_pow(<<pow_bin_list::binary-size(168)>>) do
    deserialize_pow(pow_bin_list, [])
  end

  def binary_to_pow(_) do
    {:error, "#{__MODULE__} : Illegal PoW serialization"}
  end

  defp deserialize_pow(<<pow::32, rest::binary>>, acc) do
    deserialize_pow(rest, List.insert_at(acc, -1, pow))
  end

  defp deserialize_pow(<<>>, acc) do
    if Enum.count(Enum.filter(acc, fn x -> is_integer(x) and x >= 0 end)) == 42 do
      acc
    else
      {:error, "#{__MODULE__} : Illegal PoW serialization"}
    end
  end

  @spec tag_to_type(non_neg_integer()) :: atom() | {:error, String.t()}
  def tag_to_type(10), do: Account
  def tag_to_type(30), do: Name
  def tag_to_type(31), do: NameCommitment
  def tag_to_type(40), do: ChannelStateOnChain
  def tag_to_type(20), do: Oracle
  def tag_to_type(21), do: OracleQuery
  def tag_to_type(11), do: SignedTx
  def tag_to_type(100), do: Block

  def tag_to_type(12), do: SpendTx
  def tag_to_type(22), do: OracleRegistrationTx
  def tag_to_type(23), do: OracleQueryTx
  def tag_to_type(24), do: OracleResponseTx
  def tag_to_type(25), do: OracleExtendTx
  def tag_to_type(31), do: NameCommitment
  def tag_to_type(32), do: NameClaimTx
  def tag_to_type(33), do: NamePreClaimTx
  def tag_to_type(34), do: NameUpdateTx
  def tag_to_type(35), do: NameRevokeTx
  def tag_to_type(36), do: NameTransferTx
  def tag_to_type(50), do: ChannelCreateTx
  def tag_to_type(53), do: ChannelCloseMutalTx
  def tag_to_type(54), do: ChannelCloseSoloTx
  def tag_to_type(55), do: ChannelSlashTx
  def tag_to_type(57), do: ChannelSettleTx
  def tag_to_type(tag), do: {:error, "#{__MODULE__} : Unknown TX Tag: #{inspect(tag)}"}

  @spec type_to_tag(atom()) :: non_neg_integer() | {:error, String.t()}
  def type_to_tag(SpendTx), do: 12
  def type_to_tag(OracleRegistrationTx), do: 22
  def type_to_tag(OracleQueryTx), do: 23
  def type_to_tag(OracleResponseTx), do: 24
  def type_to_tag(OracleExtendTx), do: 25
  def type_to_tag(NameClaimTx), do: 32
  def type_to_tag(NamePreClaimTx), do: 33
  def type_to_tag(NameUpdateTx), do: 34
  def type_to_tag(NameRevokeTx), do: 35
  def type_to_tag(NameTransferTx), do: 36
  def type_to_tag(ChannelCreateTx), do: 50
  def type_to_tag(ChannelCloseMutalTx), do: 53
  def type_to_tag(ChannelCloseSoloTx), do: 54
  def type_to_tag(ChannelSlashTx), do: 55
  def type_to_tag(ChannelSettleTx), do: 57
  def type_to_tag(type), do: {:error, "#{__MODULE__} : Unknown TX Type: #{type}"}

  @spec get_version(atom()) :: non_neg_integer() | {:error, String.t()}
  def get_version(Name), do: {:ok, 1}
  def get_version(NameCommitment), do: {:ok, 1}
  def get_version(ChannelStateOnChain), do: {:ok, 1}
  def get_version(Account), do: {:ok, 1}
  def get_version(Oracle), do: {:ok, 1}
  def get_version(OracleQuery), do: {:ok, 1}
end
