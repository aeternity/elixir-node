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
  alias Aecore.Structures.OracleRegistrationTx
  alias Aecore.Structures.OracleQueryTx
  alias Aecore.Structures.OracleResponseTx
  alias Aecore.Structures.OracleExtendTx
  alias Aeutil.Bits
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Oracle.Tx.OracleExtendTx
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Oracle.Tx.OracleRegistrationTx
  alias Aecore.Oracle.Tx.OracleResponseTx
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Account.Tx.CoinbaseTx

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
          senders: list(binary()),
          fee: non_neg_integer(),
          nonce: non_neg_integer()
        }

  @doc """
  Definition of Aecore DataTx structure

  ## Parameters
  - type: The type of transaction that may be added to the blockchain
  - payload: The strcuture of the specified transaction type
  - senders: The public addresses of the accounts originating the transaction. First element of this list is special - it's the main sender. Nonce is applied to main sender Account.
  - fee: The amount of tokens given to the miner
  - nonce: An integer bigger then current nonce of main sender Account. (see senders)
  """
  defstruct [:type, :payload, :senders, :fee, :nonce]
  use ExConstructor

  def valid_types do
    [
      Aecore.Account.Tx.SpendTx,
      Aecore.Account.Tx.CoinbaseTx,
      Aecore.Oracle.Tx.OracleExtendTx,
      Aecore.Oracle.Tx.OracleQueryTx,
      Aecore.Oracle.Tx.OracleRegistrationTx,
      Aecore.Oracle.Tx.OracleResponseTx,
      Aecore.Naming.Tx.NameClaimTx,
      Aecore.Naming.Tx.NamePreClaimTx,
      Aecore.Naming.Tx.NameRevokeTx,
      Aecore.Naming.Tx.NameTransferTx,
      Aecore.Naming.Tx.NameUpdateTx
    ]
  end

  @spec init(tx_types(), payload(), list(binary()) | binary(), non_neg_integer(), integer()) ::
          DataTx.t()
  def init(type, payload, senders, fee, nonce) when is_list(senders) do
    %DataTx{type: type, payload: type.init(payload), senders: senders, nonce: nonce, fee: fee}
  end

  def init(type, payload, sender, fee, nonce) when is_binary(sender) do
    %DataTx{type: type, payload: type.init(payload), senders: [sender], nonce: nonce, fee: fee}
  end

  @spec fee(DataTx.t()) :: non_neg_integer()
  def fee(%DataTx{fee: fee}) do
    fee
  end

  @spec senders(DataTx.t()) :: list(binary())
  def senders(%DataTx{senders: senders}) do
    senders
  end

  @spec main_sender(DataTx.t()) :: binary() | nil
  def main_sender(tx) do
    List.first(senders(tx))
  end

  @spec nonce(DataTx.t()) :: non_neg_integer()
  def nonce(%DataTx{nonce: nonce}) do
    nonce
  end

  @spec payload(DataTx.t()) :: map()
  def payload(%DataTx{payload: payload, type: type}) do
    if Enum.member?(valid_types(), type) do
      type.init(payload)
    else
      Logger.error("Call to DataTx payload with invalid transaction type")
      %{}
    end
  end

  @doc """
  Checks whether the fee is above 0.
  """
  @spec validate(DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%DataTx{fee: fee, type: type} = tx) do
    cond do
      !Enum.member?(valid_types(), type) ->
        {:error, "#{__MODULE__}: Invalid tx type=#{type}"}

      fee < 0 ->
        {:error, "#{__MODULE__}: Negative fee"}

      !senders_pubkeys_size_valid?(tx.senders) ->
        {:error, "#{__MODULE__}: Invalid senders pubkey size"}

      true ->
        payload_validate(tx)
    end
  end

  @doc """
  Changes the chainstate (account state and tx_type_state) according
  to the given transaction requirements
  """
  @spec process_chainstate(ChainState.chainstate(), non_neg_integer(), DataTx.t()) ::
          {:ok, ChainState.chainstate()} | {:error, String.t()}
  def process_chainstate(chainstate, block_height, %DataTx{fee: fee} = tx) do
    accounts_state = chainstate.accounts
    payload = payload(tx)

    tx_type_state = Map.get(chainstate, tx.type.get_chain_state_name(), %{})
    IO.inspect("$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$")
    IO.inspect(block_height)
    IO.inspect("$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$$")

    nonce_accounts_state =
      if Enum.empty?(tx.senders) do
        accounts_state
      else
        AccountStateTree.update(accounts_state, main_sender(tx), fn acc ->
          Account.apply_nonce!(acc, tx.nonce)
        end)
      end

    with {:ok, {new_accounts_state, new_tx_type_state}} <-
           nonce_accounts_state
           |> tx.type.deduct_fee(block_height, payload, tx, fee)
           |> tx.type.process_chainstate(
             tx_type_state,
             block_height,
             payload,
             tx
           ) do
      new_chainstate =
        if tx.type.get_chain_state_name() == nil do
          %{chainstate | accounts: new_accounts_state}
        else
          %{chainstate | accounts: new_accounts_state}
          |> Map.put(tx.type.get_chain_state_name(), new_tx_type_state)
        end

      {:ok, new_chainstate}
    else
      err ->
        err
    end
  end

  @spec preprocess_check(ChainState.chainstate(), non_neg_integer(), DataTx.t()) ::
          :ok | {:error, String.t()}
  def preprocess_check(chainstate, block_height, tx) do
    accounts_state = chainstate.accounts
    payload = payload(tx)
    tx_type_state = Map.get(chainstate, tx.type.get_chain_state_name(), %{})

    with :ok <- tx.type.preprocess_check(accounts_state, tx_type_state, block_height, payload, tx) do
      if main_sender(tx) == nil || Account.nonce(chainstate.accounts, main_sender(tx)) < tx.nonce do
        :ok
      else
        {:error, "#{__MODULE__}: Too small nonce"}
      end
    else
      err ->
        err
    end
  end

  @spec serialize(DataTx.t()) :: map()
  def serialize(%DataTx{} = tx) do
    map_without_senders = %{
      "type" => Serialization.serialize_value(tx.type),
      "payload" => Serialization.serialize_value(tx.payload),
      "fee" => Serialization.serialize_value(tx.fee),
      "nonce" => Serialization.serialize_value(tx.nonce)
    }

    if length(tx.senders) == 1 do
      Map.put(
        map_without_senders,
        "sender",
        Serialization.serialize_value(main_sender(tx), :sender)
      )
    else
      Map.put(map_without_senders, "senders", Serialization.serialize_value(tx.senders, :sender))
    end
  end

  @spec deserialize(map()) :: DataTx.t()
  def deserialize(%{sender: sender} = data_tx) do
    init(data_tx.type, data_tx.payload, [sender], data_tx.fee, data_tx.nonce)
  end

  def deserialize(%{senders: senders} = data_tx) do
    init(data_tx.type, data_tx.payload, senders, data_tx.fee, data_tx.nonce)
  end

  def base58c_encode(bin) do
    Bits.encode58c("th", bin)
  end

  def base58c_decode(<<"th$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "#{__MODULE__}: Wrong data"}
  end

  @spec standard_deduct_fee(
          AccountStateTree.accounts_state(),
          non_neg_integer(),
          DataTx.t(),
          non_neg_integer()
        ) :: Account.t()
  def standard_deduct_fee(accounts, block_height, data_tx, fee) do
    sender = DataTx.main_sender(data_tx)

    AccountStateTree.update(accounts, sender, fn acc ->
      Account.apply_transfer!(acc, block_height, fee * -1)
    end)
  end

  defp payload_validate(%DataTx{type: type, payload: payload} = data_tx) do
    payload
    |> type.init()
    |> type.validate(data_tx)
  end

  defp senders_pubkeys_size_valid?([sender | rest]) do
    if Wallet.key_size_valid?(sender) do
      senders_pubkeys_size_valid?(rest)
    else
      false
    end
  end

  defp senders_pubkeys_size_valid?([]) do
    true
  end

  @spec rlp_encode(DataTx.t()) :: binary() | {:error, String.t()}
  def rlp_encode(%DataTx{type: SpendTx} = tx) do
    [
      type_to_tag(SpendTx),
      get_version(SpendTx),
      tx.senders,
      tx.payload.receiver,
      tx.payload.amount,
      tx.fee,
      tx.nonce,
      tx.payload.payload
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: CoinbaseTx} = tx) do
    [
      type_to_tag(CoinbaseTx),
      get_version(CoinbaseTx),
      tx.payload.receiver,
      tx.nonce,
      tx.payload.amount
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: OracleRegistrationTx} = tx) do
    ttl_type = Serialization.encode_ttl_type(tx.payload.ttl)

    [
      type_to_tag(OracleRegistrationTx),
      get_version(OracleRegistrationTx),
      tx.senders,
      tx.nonce,
      Serialization.transform_item(tx.payload.query_format),
      Serialization.transform_item(tx.payload.response_format),
      tx.payload.query_fee,
      ttl_type,
      tx.payload.ttl.ttl,
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
      tx.senders,
      tx.nonce,
      tx.payload.oracle_address,
      Serialization.transform_item(tx.payload.query_data),
      tx.payload.query_fee,
      ttl_type_q,
      tx.payload.query_ttl.ttl,
      ttl_type_r,
      tx.payload.response_ttl.ttl,
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: OracleResponseTx} = tx) do
    [
      type_to_tag(OracleResponseTx),
      get_version(OracleResponseTx),
      # oracle? not confirmed
      tx.senders,
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
    [
      type_to_tag(OracleExtendTx),
      get_version(OracleExtendTx),
      tx.senders,
      tx.nonce,
      tx.payload.ttl,
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: NamePreClaimTx} = tx) do
    [
      type_to_tag(NamePreClaimTx),
      get_version(NamePreClaimTx),
      tx.senders,
      tx.nonce,
      tx.payload.commitment,
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: NameClaimTx} = tx) do
    [
      type_to_tag(NameClaimTx),
      get_version(NameClaimTx),
      tx.senders,
      tx.nonce,
      tx.payload.name,
      tx.payload.name_salt,
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: NameUpdateTx} = tx) do
    [
      type_to_tag(NameUpdateTx),
      get_version(NameUpdateTx),
      tx.senders,
      tx.nonce,
      tx.payload.hash,
      tx.payload.client_ttl,
      tx.payload.pointers,
      tx.payload.expire_by,
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: NameRevokeTx} = tx) do
    [
      type_to_tag(NameRevokeTx),
      get_version(NameRevokeTx),
      tx.senders,
      tx.nonce,
      tx.payload.hash,
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(%DataTx{type: NameTransferTx} = tx) do
    [
      type_to_tag(NameTransferTx),
      get_version(NameTransferTx),
      tx.senders,
      tx.nonce,
      tx.payload.hash,
      tx.payload.target,
      tx.fee
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(data) when is_binary(data) or is_integer(data) do
    ExRLP.encode(data)
  end

  def rlp_encode(tx) do
    {:error, "Invalid DataTx: #{inspect(tx)}"}
  end

  @spec rlp_decode(binary()) :: tx_types() | {:error, String.t()}
  def rlp_decode(values) when is_binary(values) do
    [tag_bin, ver_bin | rest_data] = ExRLP.decode(values)
    tag = Serialization.transform_item(tag_bin, :int)
    _ver = Serialization.transform_item(ver_bin, :int)
    decode(tag_to_type(tag), rest_data)
  end

  def rlp_decode(data) when is_binary(data) do
    ExRLP.decode(data)
  end

  defp decode(SpendTx, [senders, receiver, amount, fee, nonce, payload]) do
    DataTx.init(
      SpendTx,
      %{
        receiver: receiver,
        amount: Serialization.transform_item(amount, :int),
        version: 1,
        payload: payload
      },
      senders,
      Serialization.transform_item(fee, :int),
      Serialization.transform_item(nonce, :int)
    )
  end

  defp decode(CoinbaseTx, [receiver, nonce, amount]) do
    DataTx.init(
      CoinbaseTx,
      %{
        receiver: receiver,
        amount: Serialization.transform_item(amount, :int)
      },
      [],
      0,
      Serialization.transform_item(nonce, :int)
    )
  end

  defp decode(OracleQueryTx, [
         senders,
         nonce,
         oracle_address,
         query_data,
         query_fee,
         query_ttl_type,
         query_ttl_value,
         response_ttl_type,
         response_ttl_value,
         fee
       ]) do
    q_ttl_type =
      query_ttl_type
      |> Serialization.transform_item(:int)
      |> Serialization.decode_ttl_type()

    r_ttl_type =
      response_ttl_type
      |> Serialization.transform_item(:int)
      |> Serialization.decode_ttl_type()

    payload = %{
      oracle_address: oracle_address,
      query_data: query_data,
      query_fee: Serialization.transform_item(query_fee, :int),
      query_ttl: %{ttl: Serialization.transform_item(query_ttl_value, :int), type: q_ttl_type},
      response_ttl: %{
        ttl: Serialization.transform_item(response_ttl_value, :int),
        type: r_ttl_type
      }
    }

    DataTx.init(
      OracleQueryTx,
      payload,
      senders,
      Serialization.transform_item(fee, :int),
      Serialization.transform_item(nonce, :int)
    )
  end

  defp decode(OracleRegistrationTx, [
         senders,
         nonce,
         query_format,
         response_format,
         query_fee,
         ttl_type,
         ttl_value,
         fee
       ]) do
    ttl_t =
      ttl_type
      |> Serialization.transform_item(:int)
      |> Serialization.decode_ttl_type()

    payload = %{
      query_format: Serialization.transform_item(query_format, :binary),
      response_format: Serialization.transform_item(response_format, :binary),
      ttl: %{ttl: Serialization.transform_item(ttl_value, :int), type: ttl_t},
      query_fee: Serialization.transform_item(query_fee, :int)
    }

    DataTx.init(
      OracleRegistrationTx,
      payload,
      senders,
      Serialization.transform_item(fee, :int),
      Serialization.transform_item(nonce, :int)
    )
  end

  defp decode(OracleResponseTx, [senders, nonce, query_id, response, fee]) do
    payload = %{
      query_id: Serialization.transform_item(query_id, :binary),
      response: Serialization.transform_item(response, :binary)
    }

    DataTx.init(
      OracleResponseTx,
      payload,
      senders,
      Serialization.transform_item(fee, :int),
      Serialization.transform(nonce, :int)
    )
  end

  defp decode(OracleExtendTx, [senders, nonce, ttl_value, fee]) do
    payload = %{
      ttl: Serialization.transform_item(ttl_value, :int)
    }

    DataTx.init(
      OracleExtendTx,
      payload,
      senders,
      Serialization.transform_item(fee, :int),
      Serialization.transform_item(nonce, :int)
    )
  end

  defp decode(NamePreClaimTx, [senders, nonce, commitment, fee]) do
    payload = %NamePreClaimTx{commitment: commitment}

    DataTx.init(
      NamePreClaimTx,
      payload,
      senders,
      Serialization.transform_item(fee, :int),
      Serialization.transform_item(nonce, :int)
    )
  end

  defp decode(NameClaimTx, [senders, nonce, name, name_salt, fee]) do
    payload = %NameClaimTx{name: name, name_salt: name_salt}

    DataTx.init(
      NameClaimTx,
      payload,
      senders,
      Serialization.transform_item(fee, :int),
      Serialization.transform_item(nonce, :int)
    )
  end

  defp decode(NameUpdateTx, [senders, nonce, hash, name_ttl, pointers, ttl, fee]) do
    payload = %NameUpdateTx{
      client_ttl: Serialization.transform_item(ttl, :int),
      expire_by: Serialization.transform_item(name_ttl, :int),
      hash: hash,
      pointers: pointers
    }

    DataTx.init(
      NameUpdateTx,
      payload,
      senders,
      Serialization.transform_item(fee, :int),
      Serialization.transform_item(nonce, :int)
    )
  end

  defp decode(NameRevokeTx, [senders, nonce, hash, fee]) do
    payload = %NameRevokeTx{hash: hash}

    DataTx.init(
      NameRevokeTx,
      payload,
      senders,
      Serialization.transform_item(fee, :int),
      Serialization.transform_item(nonce, :int)
    )
  end

  defp decode(NameTransferTx, [senders, nonce, hash, recipient, fee]) do
    payload = %NameTransferTx{hash: hash, target: recipient}

    DataTx.init(
      NameTransferTx,
      payload,
      senders,
      Serialization.transform_item(fee, :int),
      Serialization.transform_item(nonce, :int)
    )
  end

  defp decode(_, _) do
    {:error, "Unknown DataTx structure"}
  end

  @spec type_to_tag(atom()) :: non_neg_integer() | {:error, String.t()}
  defp type_to_tag(SpendTx), do: 12
  defp type_to_tag(CoinbaseTx), do: 13
  defp type_to_tag(OracleRegistrationTx), do: 22
  defp type_to_tag(OracleQueryTx), do: 23
  defp type_to_tag(OracleResponseTx), do: 24
  defp type_to_tag(OracleExtendTx), do: 25
  defp type_to_tag(NameName), do: 30
  defp type_to_tag(NameCommitment), do: 31
  defp type_to_tag(NameClaimTx), do: 32
  defp type_to_tag(NamePreClaimTx), do: 33
  defp type_to_tag(NameUpdateTx), do: 34
  defp type_to_tag(NameRevokeTx), do: 35
  defp type_to_tag(NameTransferTx), do: 36

  defp type_to_tag(type), do: {:error, "Unknown TX Type: #{type}"}

  @spec tag_to_type(non_neg_integer()) :: tx_types() | {:error, String.t()}
  defp tag_to_type(12), do: SpendTx
  defp tag_to_type(13), do: CoinbaseTx
  defp tag_to_type(22), do: OracleRegistrationTx
  defp tag_to_type(23), do: OracleQueryTx
  defp tag_to_type(24), do: OracleResponseTx
  defp tag_to_type(25), do: OracleExtendTx
  defp tag_to_type(30), do: NameName
  defp tag_to_type(31), do: NameCommitment
  defp tag_to_type(32), do: NameClaimTx
  defp tag_to_type(33), do: NamePreClaimTx
  defp tag_to_type(34), do: NameUpdateTx
  defp tag_to_type(35), do: NameRevokeTx
  defp tag_to_type(36), do: NameTransferTx
  defp tag_to_type(tag), do: {:error, "Unknown TX Tag: #{inspect(tag)}"}

  @spec get_version(tx_types()) :: non_neg_integer() | {:error, String.t()}
  defp get_version(SpendTx), do: 1
  defp get_version(CoinbaseTx), do: 1
  defp get_version(OracleRegistrationTx), do: 1
  defp get_version(OracleQueryTx), do: 1
  defp get_version(OracleResponseTx), do: 1
  defp get_version(OracleExtendTx), do: 1
  defp get_version(NameName), do: 1
  defp get_version(NameCommitment), do: 1
  defp get_version(NameClaimTx), do: 1
  defp get_version(NamePreClaimTx), do: 1
  defp get_version(NameUpdateTx), do: 1
  defp get_version(NameRevokeTx), do: 1
  defp get_version(NameTransferTx), do: 1

  defp get_version(ver), do: {:error, "Unknown Struct version: #{inspect(ver)}"}
end
