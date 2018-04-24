defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Oracle.Tx.OracleRegistrationTx
  alias Aecore.Oracle.Tx.OracleExtendTx
  alias Aecore.Oracle.Tx.OracleResponseTx
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Chain.Chainstate
  alias Aeutil.Parser
  alias Aecore.Account.Account
  alias Aecore.Account.Tx.SpendTx

  require Logger

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
          Map.put(new_value, Parser.to_atom(key), deserialize_value(val, Parser.to_atom(key)))
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
        Parser.to_atom(value)
    end
  end

  def deserialize_value(value, _), do: value

  @spec serialize_txs_info_to_json(list(raw_data())) :: list(map())
  def serialize_txs_info_to_json(txs_info) when is_list(txs_info) do
    serialize_txs_info_to_json(txs_info, [])
  end

  defp serialize_txs_info_to_json([h | t], acc) do
    tx = DataTx.init(h.type, h.payload, h.sender, h.fee, h.nonce)
    tx_hash = SignedTx.hash_tx(%SignedTx{data: tx, signature: nil})

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
      hash: DataTx.base58c_encode(tx_hash),
      signatures: [SignedTx.base58c_encode_signature(h.signature)]
    }

    acc = [json_response_struct | acc]
    serialize_txs_info_to_json(t, acc)
  end

  defp serialize_txs_info_to_json([], acc) do
    Enum.reverse(acc)
  end
@spec rlp_encode(DataTx.t(SignedTx.t())) :: binary()
  def rlp_encode(%SignedTx{} = tx) do
      signatures = for sig <- [tx.signature] do
        if sig == nil do
          ExRLP.encode(<<0>>)
        else
          ExRLP.encode(sig)
        end
      end
    ExRLP.encode([type_to_tag(SignedTx), 1, signatures, rlp_encode(tx.data)])
  end
  @spec rlp_encode(DataTx.t(SpendTx.t())) :: binary()
  def rlp_encode(%DataTx{type: SpendTx} = tx) do

    if tx.sender == nil do
      [
        type_to_tag(CoinbaseTx),
        get_version(CoinbaseTx),
        tx.payload.receiver, #receiver
        # Subject to discuss/change:
        # CoinbaseTx Should have a "height" field, currently "nonce" is being encoded
        tx.nonce, #nonce / but should be height
        tx.payload.amount #reward
      ]
    else
      [
        type_to_tag(SpendTx),
        get_version(SpendTx),
        tx.sender, # sender
        tx.payload.receiver, #receiver
        tx.payload.amount, #amount
        tx.fee, # fee
        tx.nonce # nonce
      ]
    end
    |> ExRLP.encode()
  end
  @spec rlp_encode(DataTx.t()) :: binary()
  def rlp_encode(%DataTx{type: CoinbaseTx} = tx) do

    [
      type_to_tag(CoinbaseTx),
      get_version(CoinbaseTx),
      tx.payload.receiver, #receiver
      # Subject to discuss/change:: Here should be Height, but at this moment nonce is being encoded
      tx.nonce, # nonce / but should be height
      tx.payload.amount #amount
    ]
    |> ExRLP.encode()
  end
  @spec rlp_encode(DataTx.t(OracleRegistrationTx.t())) :: binary()
  def rlp_encode(%DataTx{type: OracleRegistrationTx} = tx) do
    ttl_type = encode_ttl_type(tx.payload.ttl)

    [
      type_to_tag(OracleRegistrationTx),
      get_version(OracleRegistrationTx),
      tx.sender, #account
      tx.nonce,  #nonce
      # Subject to discuss/change:
      # In Erlang core it is described as a UTF8 encoded String, but we have a map here
      transform_item(tx.payload.query_format), #query_format/spec
      # Subject to discuss/change:
      # In Erlang core it is described as a UTF8 encoded String, but we have a map here
      transform_item(tx.payload.response_format), #query_response/spec
      tx.payload.query_fee, #query_fee
      ttl_type, # ttl_type
      tx.payload.ttl.ttl, #ttl_value
      tx.fee #fee
    ]
    |> ExRLP.encode()
  end
  @spec rlp_encode(DataTx.t(OracleQueryTx.t())) :: binary()
  def rlp_encode(%DataTx{type: OracleQueryTx} = tx) do
    ttl_type_q = encode_ttl_type(tx.payload.query_ttl)
    ttl_type_r = encode_ttl_type(tx.payload.response_ttl)

    [
      type_to_tag(OracleQueryTx),
      get_version(OracleQueryTx),
      tx.sender, #sender
      tx.nonce,  #nonce
      tx.payload.oracle_address, #oracle
      # Subject to discuss/change:
      # In Erlang core query_data is described as a binary,
      # but not encoded "natively"(query_data in our case is a map)
      transform_item(tx.payload.query_data), #query
      tx.payload.query_fee, #query_fee
      ttl_type_q, #query_ttl_type
      tx.payload.query_ttl.ttl, #query_ttl_value
      ttl_type_r, #response_ttl_type
      tx.payload.response_ttl.ttl, #response_ttl_value
      tx.fee #fee
    ]
    |> ExRLP.encode()
  end
  @spec rlp_encode(DataTx.t(OracleResponseTx.t())) :: binary()
  def rlp_encode(%DataTx{type: OracleResponseTx} = tx) do

    [
      type_to_tag(OracleResponseTx),
      get_version(OracleResponseTx),
      tx.sender, #oracle? not confirmed
      tx.nonce, #nonce
      tx.payload.query_id, #query_id
      transform_item(tx.payload.response), #response
      tx.fee #fee
    ]
    |> ExRLP.encode()
  end
  @spec rlp_encode(DataTx.t(OracleExtendTx.t())) :: binary()
  def rlp_encode(%DataTx{type: OracleExtendTx} = tx) do
    ttl_type = encode_ttl_type(tx.payload.ttl)

    [
      type_to_tag(OracleExtendTx),
      get_version(OracleExtendTx),
      tx.sender, #oracle? not confirmed
      tx.nonce,  #nonce
      ttl_type,  #ttl_type
      tx.payload.ttl.ttl, #ttl_value
      tx.fee #fee
    ]
    |> ExRLP.encode()
  end

  @spec rlp_encode(Account.t(), Wallet.pubkey()) :: binary()
  def rlp_encode(%Account{} = account, pkey) do
    [
      type_to_tag(Account),
      get_version(Account),
      pkey, #pubkey ,
      account.nonce, #nonce
      account.last_updated,    #height
      account.balance #balance
    ]
    |>
    ExRLP.encode
  end
  @spec rlp_encode(Chainstate.t(), Wallet.pubkey(), atom()) :: binary()
  def rlp_encode(%Chainstate{accounts: accounts}, pkey, :account_state) do
    account_info = Account.get_account_state(accounts, pkey)

    [
      type_to_tag(Account),
      get_version(Account),
      pkey, #pubkey
      account_info.nonce, #should be height but atm its nonce
      account_info.balance #balance
    ]
    |> ExRLP.encode()
  end
  def rlp_encode(
        %Chainstate{oracles: %{registered_oracles: registered_oracles}},
        orc_owner,
        :oracle_state
      ) do
    # list_of_formatted_data =
    # Subject to discuss field "height_included" in our structures is not being encoded , erlang" core doesnt have this field
    case Map.get(registered_oracles, orc_owner) do
      nil ->
        [
          type_to_tag(Oracle),
          get_version(Oracle),
          orc_owner, # owner
          transform_item(%{}), #query_format, should be a string(but we have a map)
          transform_item(%{}), #response_format, should be a string (but we have a map)
          0, #query_fee
          0, #expires
        ]

      data ->
        [
          type_to_tag(Oracle),
          get_version(Oracle),
          orc_owner,  # owner
          # Subject to discuss/change - In Erlang implementation its a UTF8 encoded string but in our case - map
          transform_item(data.tx.query_format), #query_format, should be a string(but we have a map)
          transform_item(data.tx.response_format), #response_format, should be a string (but we have a map)
          data.tx.query_fee, #query_fee
          # Subject to discuss/change - Erlang core has an integer field called expires, our case - map with ttl and its type :absolute/relative
         # encode_ttl_type(data.tx.ttl),
          data.tx.ttl.ttl  #"expires" doesnt exist at this moment,
        ]
    end
    |> ExRLP.encode()
  end
  def rlp_encode(
        %Chainstate{oracles: %{interaction_objects: interaction_objects}},
        sender_address,
        :oracle_query
      ) do
    case Map.get(interaction_objects, sender_address) do
      nil ->
        [
          type_to_tag(OracleQuery), #type
          get_version(OracleQuery), #ver
          sender_address, #pubkey
          0, #sender_nonce
          <<0>>, # oracle_address
          transform_item(%OracleQueryTx{}), #query
          <<0>>, #has_response
          transform_item(%OracleResponseTx{}), #response
          0, #expires
          0, #response_ttl
          0, #fee
        ]

      data ->
        [
          type_to_tag(OracleQuery), #type
          get_version(OracleQuery), #ver
          sender_address, #pubkey
          # Subject : We dont have sender_nonce field here,
          data.query.oracle_address, # oracle_address
          # Subject : Query: Equivalent here would be fully composed DataTx(OracleQueryTx) , not just OracleQueryTx
          rlp_encode(transform_item(data.query)), #query
          <<0>>,  # Subject: has_response field doesnt exist, will be hardcoded as <<0>>/false for now

          # Subject: Response: Equivalent here would be fully composed DataTx(ResponseTx), not a map
          rlp_encode(transform_item(data.query.response)), #response
          data.query.query_ttl.ttl, # Subject: no field called "expires" here, should be calculated over ttl_type and ttl_value itself
          data.query.response_ttl.ttl,
          data.query.query_fee
        ]
    end
    |> ExRLP.encode()
  end
  #  def rlp_encode(%Block{} = block) do
  #   pow_to_binary = 
  #     for pow <- block.header.pow_evidence
  #       << <<pow::32>>
  #     end
  #    [
  #     type_to_tag(Block),
  #     get_version(Block),
  #     <<block.header.version::64,
  #     block.header.height::64,
  #     block.header.prev_hash::binary,
  #     block.header.txs_hash::binary,
  #     block.header.root_hash::binary,
  #     block.header.target::64,
  #     pow_to_binary,
  #    ]
  #    |>
  #    ExRLP.encode
  #  end
  defp type_to_tag(Account), do: 10
  defp type_to_tag(SignedTx), do: 11
  defp type_to_tag(SpendTx), do: 12
  defp type_to_tag(CoinbaseTx), do: 13
  defp type_to_tag(Oracle), do: 20
  defp type_to_tag(OracleQuery), do: 21
  defp type_to_tag(OracleRegistrationTx), do: 22
  defp type_to_tag(OracleQueryTx), do: 23
  defp type_to_tag(OracleResponseTx), do: 24
  defp type_to_tag(OracleExtendTx), do: 25
  defp type_to_tag(Block), do: 100

  defp tag_to_type(10), do: Account
  defp tag_to_type(11), do: SignedTx
  defp tag_to_type(12), do: SpendTx
  defp tag_to_type(13), do: CoinbaseTx
  defp tag_to_type(20), do: Oracle
  defp tag_to_type(21), do: OracleQuery
  defp tag_to_type(22), do: OracleRegistrationTx
  defp tag_to_type(23), do: OracleQueryTx
  defp tag_to_type(24), do: OracleResponseTx
  defp tag_to_type(25), do: OracleExtendTx
  defp tag_to_type(100), do: Block

  def rlp_decode(values) when is_binary(values) do
    [tag_bin, ver_bin | rest_data] = ExRLP.decode(values)
    tag = transform_item(tag_bin, :int)
    ver = transform_item(ver_bin, :int)

    case tag_to_type(tag) do
      Account ->
        [pkey, nonce, height, balance] = rest_data
        [pkey, transform_item(nonce, :int), transform_item(height, :int), transform_item(balance, :int)]
         %Account{balance: transform_item(balance, :int), last_updated: transform_item(height, :int), nonce: transform_item(nonce, :int)}

      SignedTx ->
        [signatures, tx_data] = rest_data
        decoded_signatures = for sig <- signatures do
            ExRLP.decode(sig)
          end
        %SignedTx{data: rlp_decode(tx_data) , signature: decoded_signatures}

      SpendTx ->
        [sender, receiver, amount, fee, nonce] = rest_data

        [
          sender,
          receiver,
          transform_item(amount, :int),
          transform_item(fee, :int),
          transform_item(nonce, :int)
        ]
        DataTx.init(SpendTx,%{receiver: receiver, amount: transform_item(amount, :int), version: ver},sender,transform_item(fee, :int),transform_item(nonce, :int))

      CoinbaseTx ->
        [receiver, nonce, amount] = rest_data
        [receiver, transform_item(nonce, :int), transform_item(amount, :int)]
        %DataTx{fee: 0, nonce: transform_item(nonce, :int), payload: %SpendTx{amount: transform_item(amount, :int), receiver: receiver, version: ver}, sender: nil, type: SpendTx}
        DataTx.init(SpendTx, %{
          receiver: receiver,
          amount: transform_item(amount, :int),
          version: ver
        }, 
        nil,
        0, 
        transform_item(nonce, :int))
      Oracle ->
        [orc_owner, query_format, response_format, query_fee, ttl_type, ttl] = rest_data

        [
          orc_owner,
          transform_item(query_format, :binary),
          transform_item(response_format, :binary),
          transform_item(query_fee, :int),
          transform_item(ttl_type, :int),
          transform_item(ttl, :int)
        ]
       # DataTx.init(Oracle,)

      OracleQueryTx ->
        [
          sender,
          nonce,
          oracle_address,
          query_data,
          query_fee,
          query_ttl_type,
          query_ttl_value,
          response_ttl_type,
          response_ttl_value,
          fee
        ] = rest_data

        [
          sender,
          transform_item(nonce, :int),
          oracle_address,
          query_data,
          transform_item(query_fee, :int),
          query_ttl_type,
          transform_item(query_ttl_value, :int),
          response_ttl_type,
          transform_item(response_ttl_value, :int),
          transform_item(fee, :int)
        ]

      OracleRegistrationTx ->
        [sender, nonce, query_format, response_format, query_fee, ttl_type, ttl_value, fee] =
          rest_data

        [
          sender,
          transform_item(nonce, :int),
          transform_item(query_format, :binary),
          transform_item(response_format, :binary),
          transform_item(query_fee, :int),
          transform_item(ttl_type, :binary),
          transform_item(ttl_value, :int),
          transform_item(fee, :int)
        ]

      OracleResponseTx ->
        [sender, nonce, query_id, response, fee] = rest_data

        [
          sender,
          transform_item(nonce, :int),
          transform_item(query_id, :binary),
          transform_item(response, :binary),
          transform_item(fee, :int)
        ]

      OracleExtendTx ->
        [sender, nonce, ttl_type, ttl_value, fee] = rest_data

        [
          sender,
          transform_item(nonce, :int),
          transform_item(ttl_type, :binary),
          transform_item(ttl_value, :int),
          transform_item(fee, :int)
        ]

      _ ->
        Logger.error("Illegal serialization")
    end
  end
  def rlp_decode(binary) when is_binary(binary) do
    ExRLP.decode binary
  end
 
  #  def rlp_decode(binary,pattern) do
  #  end
  defp transform_item(item) do
    :erlang.term_to_binary(item)
  end

  defp transform_item(item, type) do
    case type do
      :int -> :binary.decode_unsigned(item)
      :binary -> :erlang.binary_to_term(item)
    end
  end

  defp get_version(type) do
    # Subject to discuss: These hardcoded versions could be stored somewhere in config file.
    case type do
      Account -> 1
      SignedTx -> 1
      SpendTx -> 1
      CoinbaseTx -> 1
      Oracle -> 1
      OracleQueryTx -> 1
      OracleRegistrationTx -> 1
      OracleResponseTx -> 1
      OracleExtendTx -> 1
      _ -> {:error, "Unknown structure type"}
    end
  end

  defp encode_ttl_type(%{type: type}) do
    case type do
      :absolute -> 0
      :relative -> 1
    end
  end

  @spec nils_to_binary(SignedTx.t()) :: Map.t()
  def nils_to_binary(tx) when is_map(tx) do
    tx = remove_struct(tx)

    Enum.reduce(tx, %{}, fn {k, v}, acc ->
      Map.put(
        acc,
        k,
        # Subject to discuss/change:
        # Added to avoid nils from SpendTx(Coin-based),
        # because CoinbaseTx doesnt have separate structure at this moment
        case v do
          %{} = v ->
            nils_to_binary(v)

          _ ->
            v
        end
      )
    end)
  end
end
