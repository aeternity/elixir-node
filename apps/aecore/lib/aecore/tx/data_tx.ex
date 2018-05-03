defmodule Aecore.Tx.DataTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """
  alias Aecore.Naming.Tx.NamePreClaimTx
  alias Aecore.Naming.Tx.NameClaimTx
  alias Aecore.Naming.Tx.NameUpdateTx
  alias Aecore.Naming.Tx.NameTransferTx
  alias Aecore.Naming.Tx.NameRevokeTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Tx.SpendTx
  alias Aeutil.Serialization
  alias Aeutil.Parser
  alias Aeutil.Bits
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Oracle.Tx.OracleExtendTx
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Oracle.Tx.OracleRegistrationTx
  alias Aecore.Oracle.Tx.OracleResponseTx
  alias Aecore.Oracle.Oracle 

  require Logger

  @typedoc "Name of the specified transaction module"
  @type tx_types ::
          SpendTx
          | OracleExtendTx
          | OracleRegistrationTx
          | OracleResponseTx
          | OracleResponseTx
          | NamePreClaimTx
          | NameClaimTx
          | NameUpdateTx
          | NameTransferTx
          | NameRevokeTx

  @typedoc "Structure of a transaction that may be added to be blockchain"
  @type payload ::
          SpendTx.t()
          | OracleExtendTx.t()
          | OracleQueryTx.t()
          | OracleRegistrationTx.t()
          | OracleResponseTx.t()
          | NamePreClaimTx.t()
          | NameClaimTx.t()
          | NameUpdateTx.t()
          | NameTransferTx.t()
          | NameRevokeTx.t()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure of the main transaction wrapper"
  @type t :: %DataTx{
          type: tx_types(),
          payload: payload(),
          sender: binary(),
          fee: non_neg_integer(),
          nonce: non_neg_integer()
        }

  @doc """
  Definition of Aecore DataTx structure

  ## Parameters
  - type: The type of transaction that may be added to the blockchain
  - payload: The strcuture of the specified transaction type
  - sender: The public address of the account originating the transaction
  - fee: The amount of tokens given to the miner
  - nonce: A random integer generated on initialisation of a transaction (must be unique!)
  """
  defstruct [:type, :payload, :sender, :fee, :nonce]
  use ExConstructor

  @spec init(tx_types(), payload(), binary(), integer(), integer()) :: DataTx.t()
  def init(type, payload, sender, fee, nonce) do
    %DataTx{type: type, payload: type.init(payload), sender: sender, fee: fee, nonce: nonce}
  end

  @doc """
  Checks whether the fee is above 0.
  """
  @spec validate(DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%DataTx{type: type, payload: payload, fee: fee}) do
    if fee > 0 do
      child_tx = type.init(payload)
      {:ok, child_tx}
    else
      {:error, "#{__MODULE__}: Fee not enough: #{inspect(fee)}"}
    end
  end

  @doc """
  Changes the chainstate (account state and tx_type_state) according
  to the given transaction requirements
  """
  @spec process_chainstate(DataTx.t(), ChainState.t(), non_neg_integer()) :: Chainstate.t()
  def process_chainstate(%DataTx{} = tx, chainstate, block_height) do
    accounts_state_tree = chainstate.accounts

    tx_type_state = get_tx_type_state(chainstate, tx.type)

    case tx.payload
         |> tx.type.init()
         |> tx.type.process_chainstate(
           tx.sender,
           tx.fee,
           tx.nonce,
           block_height,
           accounts_state_tree,
           tx_type_state
         ) do
      {:error, reason} ->
        {:error, reason}

      {new_accounts_state_tree, new_tx_type_state} ->
        new_chainstate =
          if tx.type == SpendTx do
            chainstate
          else
            Map.put(chainstate, tx.type.get_chain_state_name(), new_tx_type_state)
          end

        {:ok, Map.put(new_chainstate, :accounts, new_accounts_state_tree)}
    end
  end

  @doc """
  Gets the given transaction type state,
  if there is any stored in the chainstate
  """
  @spec get_tx_type_state(Chainstate.t(), atom()) :: map()
  def get_tx_type_state(chainstate, tx_type) do
    type = tx_type.get_chain_state_name()
    Map.get(chainstate, type, %{})
  end

  @spec validate_sender(Wallet.pubkey(), Chainstate.t()) :: :ok | {:error, String.t()}
  def validate_sender(sender, %{accounts: account}) do
    with :ok <- Wallet.key_size_valid?(sender),
         {:ok, _account_key} <- AccountStateTree.get(account, sender) do
      :ok
    else
      :none ->
        {:error, "#{__MODULE__}: The senders key: #{inspect(sender)} doesn't exist"}

      err ->
        err
    end
  end

  @spec validate_nonce(Account.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate_nonce(accounts_state, tx) do
    if tx.nonce > Account.nonce(accounts_state, tx.sender) do
      :ok
    else
      {:error, "#{__MODULE__}: Nonce is too small: #{inspect(tx.nonce)}"}
    end
  end

  @spec preprocess_check(DataTx.t(), Chainstate.t(), non_neg_integer()) ::
          :ok | {:error, String.t()}
  def preprocess_check(
        %DataTx{
          type: type,
          payload: payload,
          sender: sender,
          fee: fee,
          nonce: nonce
        } = tx,
        %{accounts: accounts} = chainstate,
        block_height
      ) do
    sender_account_state = Account.get_account_state(accounts, sender)
    tx_type_state = get_tx_type_state(chainstate, tx.type)

    type.preprocess_check(
      payload,
      sender,
      sender_account_state,
      fee,
      nonce,
      block_height,
      tx_type_state
    )
  end

  @spec serialize(DataTx.t()) :: map()
  def serialize(%DataTx{} = tx) do
    tx
    |> Map.from_struct()
    |> Enum.reduce(%{}, fn {key, value}, new_tx ->
      Map.put(new_tx, Parser.to_string!(key), Serialization.serialize_value(value))
    end)
  end

  @spec deserialize(payload()) :: DataTx.t()
  def deserialize(%{} = tx) do
    data_tx = Serialization.deserialize_value(tx)
    init(data_tx.type, data_tx.payload, data_tx.sender, data_tx.fee, data_tx.nonce)
  end

  def base58c_encode(bin) do
    Bits.encode58c("th", bin)
  end

  def base58c_decode(<<"th$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "Wrong data"}
  end

  @spec rlp_encode(DataTx.t()) :: binary() | {:error, String.t()}
  def rlp_encode(%DataTx{type: SpendTx} = tx) do
    if tx.sender == nil do
      [
        type_to_tag(CoinbaseTx),
        get_version(CoinbaseTx),
        # receiver
        tx.payload.receiver,
        # Subject to discuss/change:
        # CoinbaseTx Should have a "height" field, currently "nonce" is being encoded
        # nonce / but should be height
        tx.nonce,
        # reward
        tx.payload.amount
      ]
    else
      [
        type_to_tag(SpendTx),
        get_version(SpendTx),
        # sender
        tx.sender,
        # receiver
        tx.payload.receiver,
        # amount
        tx.payload.amount,
        # fee
        tx.fee,
        # nonce
        tx.nonce
      ]
    end
    |> ExRLP.encode()
  end

  # TODO: add CoinbaseTx.t() to this spec
  @spec rlp_encode(DataTx.t()) :: binary()
  def rlp_encode(%DataTx{type: CoinbaseTx} = tx) do
    [
      type_to_tag(CoinbaseTx),
      get_version(CoinbaseTx),
      # receiver
      tx.payload.receiver,
      # Subject to discuss/change:: Here should be Height, but at this moment nonce is being encoded
      # nonce / but should be height
      tx.nonce,
      # amount
      tx.payload.amount
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: OracleRegistrationTx} = tx) do
    ttl_type = Serialization.encode_ttl_type(tx.payload.ttl)

    [
      type_to_tag(OracleRegistrationTx),
      get_version(OracleRegistrationTx),
      # account
      tx.sender,
      # nonce
      tx.nonce,
      # Subject to discuss/change:
      # In Erlang core it is described as a UTF8 encoded String, but we have a map here
      # query_format/spec
      Serialization.transform_item(tx.payload.query_format),
      # Subject to discuss/change:
      # In Erlang core it is described as a UTF8 encoded String, but we have a map here
      # query_response/spec
      Serialization.transform_item(tx.payload.response_format),
      # query_fee
      tx.payload.query_fee,
      # ttl_type
      ttl_type,
      # ttl_value
      tx.payload.ttl.ttl,
      # fee
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: OracleQueryTx} = tx) do
    ttl_type_q = Serialization.encode_ttl_type(tx.payload.query_ttl)
    ttl_type_r = Serialization.encode_ttl_type(tx.payload.response_ttl)

    [
      type_to_tag(OracleQueryTx),
      get_version(OracleQueryTx),
      # sender
      tx.sender,
      # nonce
      tx.nonce,
      # oracle
      tx.payload.oracle_address,
      # Subject to discuss/change:
      # In Erlang core query_data is described as a binary,
      # but not encoded "natively"(query_data in our case is a map)
      # query
      Serialization.transform_item(tx.payload.query_data),
      # query_fee
      tx.payload.query_fee,
      # query_ttl_type
      ttl_type_q,
      # query_ttl_value
      tx.payload.query_ttl.ttl,
      # response_ttl_type
      ttl_type_r,
      # response_ttl_value
      tx.payload.response_ttl.ttl,
      # fee
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: OracleResponseTx} = tx) do
    [
      type_to_tag(OracleResponseTx),
      get_version(OracleResponseTx),
      # oracle? not confirmed
      tx.sender,
      # nonce
      tx.nonce,
      # query_id
      tx.payload.query_id,
      # response
      Serialization.transform_item(tx.payload.response),
      # fee
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: OracleExtendTx} = tx) do
    ttl_type = Serialization.encode_ttl_type(tx.payload.ttl)

    [
      type_to_tag(OracleExtendTx),
      get_version(OracleExtendTx),
      # oracle? not confirmed
      tx.sender,
      # nonce
      tx.nonce,
      # ttl_type
      ttl_type,
      # ttl_value
      tx.payload.ttl.ttl,
      # fee
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(data) when is_binary(data) do
    ExRLP.encode(data)
  end

  def rlp_encode(_) do
    {:error, "Invalid Data"}
  end

  @spec rlp_decode(binary()) :: tx_types() | {:error, String.t()}
  def rlp_decode(values) when is_binary(values) do
    [tag_bin, ver_bin | rest_data] = ExRLP.decode(values)
    tag = Serialization.transform_item(tag_bin, :int)
    ver = Serialization.transform_item(ver_bin, :int)

    case tag_to_type(tag) do
      SpendTx ->
        [sender, receiver, amount, fee, nonce] = rest_data

        [
          sender,
          receiver,
          Serialization.transform_item(amount, :int),
          Serialization.transform_item(fee, :int),
          Serialization.transform_item(nonce, :int)
        ]

        DataTx.init(
          SpendTx,
          %{receiver: receiver, amount: Serialization.transform_item(amount, :int), version: ver},
          sender,
          Serialization.transform_item(fee, :int),
          Serialization.transform_item(nonce, :int)
        )

      CoinbaseTx ->
        [receiver, nonce, amount] = rest_data

        [
          receiver,
          Serialization.transform_item(nonce, :int),
          Serialization.transform_item(amount, :int)
        ]

        %DataTx{
          fee: 0,
          nonce: Serialization.transform_item(nonce, :int),
          payload: %SpendTx{
            amount: Serialization.transform_item(amount, :int),
            receiver: receiver,
            version: ver
          },
          sender: nil,
          type: SpendTx
        }

        DataTx.init(
          SpendTx,
          %{
            receiver: receiver,
            amount: Serialization.transform_item(amount, :int),
            version: ver
          },
          nil,
          0,
          Serialization.transform_item(nonce, :int)
        )

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
          Serialization.transform_item(nonce, :int),
          oracle_address,
          query_data,
          Serialization.transform_item(query_fee, :int),
          query_ttl_type,
          Serialization.transform_item(query_ttl_value, :int),
          response_ttl_type,
          Serialization.transform_item(response_ttl_value, :int),
          Serialization.transform_item(fee, :int)
        ]

      OracleRegistrationTx ->
        [sender, nonce, query_format, response_format, query_fee, ttl_type, ttl_value, fee] =
          rest_data

        [
          sender,
          Serialization.transform_item(nonce, :int),
          Serialization.transform_item(query_format, :binary),
          Serialization.transform_item(response_format, :binary),
          Serialization.transform_item(query_fee, :int),
          Serialization.transform_item(ttl_type, :binary),
          Serialization.transform_item(ttl_value, :int),
          Serialization.transform_item(fee, :int)
        ]

      OracleResponseTx ->
        [sender, nonce, query_id, response, fee] = rest_data

        [
          sender,
          Serialization.transform_item(nonce, :int),
          Serialization.transform_item(query_id, :binary),
          Serialization.transform_item(response, :binary),
          Serialization.transform_item(fee, :int)
        ]

      OracleExtendTx ->
        [sender, nonce, ttl_type, ttl_value, fee] = rest_data

        [
          sender,
          Serialization.transform_item(nonce, :int),
          Serialization.transform_item(ttl_type, :binary),
          Serialization.transform_item(ttl_value, :int),
          Serialization.transform_item(fee, :int)
        ]

      _ ->
        {:error, "Illegal DataTx serialization"}
    end
  end

  def rlp_decode(data) when is_binary(data) do
    ExRLP.decode(data)
  end

  @spec type_to_tag(atom()) :: integer() | atom()
  defp type_to_tag(SpendTx), do: 12
  defp type_to_tag(CoinbaseTx), do: 13
  defp type_to_tag(OracleRegistrationTx), do: 22
  defp type_to_tag(OracleQueryTx), do: 23
  defp type_to_tag(OracleResponseTx), do: 24
  defp type_to_tag(OracleExtendTx), do: 25
  defp type_to_tag(_), do: :unknown_type

  @spec tag_to_type(integer()) :: tx_types() | atom()
  defp tag_to_type(12), do: SpendTx
  defp tag_to_type(13), do: CoinbaseTx
  defp tag_to_type(22), do: OracleRegistrationTx
  defp tag_to_type(23), do: OracleQueryTx
  defp tag_to_type(24), do: OracleResponseTx
  defp tag_to_type(25), do: OracleExtendTx
  defp tag_to_type(_), do: :unknown_tag

  @spec get_version(tx_types()) :: integer() | atom()
  defp get_version(SpendTx), do: 1
  defp get_version(CoinbaseTx), do: 1
  defp get_version(OracleRegistrationTx), do: 1
  defp get_version(OracleQueryTx), do: 1
  defp get_version(OracleResponseTx), do: 1
  defp get_version(OracleExtendTx), do: 1
  defp get_version(_), do: :unknown_struct_version
end
