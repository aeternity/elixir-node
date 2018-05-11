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
  alias Aeutil.Bits
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Chainstate

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
           |> tx.type.deduct_fee(payload, block_height, tx, fee)
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

  @spec preprocess_check(Chainstate.t(), non_neg_integer(), DataTx.t()) ::
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
  def deserialize(%{} = data_tx) do
    senders =
      if data_tx.sender != nil do
        [data_tx.sender]
      else
        data_tx.senders
      end

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
          AccountStateTree.t(),
          DataTx.t(),
          non_neg_integer(),
          non_neg_integer()
        ) :: ChainState.account()
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
end
