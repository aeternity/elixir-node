defmodule Aecore.Structures.DataTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  alias Aecore.Structures.DataTx
  alias Aecore.Chain.ChainState
  alias Aeutil.Serialization
  alias Aeutil.Parser
  alias Aecore.Structures.Account
  alias Aeutil.MapUtil

  require Logger

  @typedoc "Name of the specified transaction module"
  @type tx_types :: SpendTx

  @typedoc "Structure of a transaction that may be added to be blockchain"
  @type payload :: SpendTx.t()

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
  - senders: The public addresses of the accounts originating the transaction
  - fee: The amount of tokens given to the miner
  - nonce: A random integer generated on initialisation of a transaction (must be unique!)
  """
  defstruct [:type, :payload, :senders, :fee, :nonce]
  use ExConstructor

  def valid_types() do [Aecore.Structures.SpendTx,
                        Aecore.Structures.CoinbaseTx,
                        Aecore.Structures.OracleExtendTx,
                        Aecore.Structures.OracleQueryTx,
                        Aecore.Structures.OracleRegistrationTx,
                        Aecore.Structures.OracleResponseTx] end

  @spec init(tx_types(), payload(), list(binary()) | binary(), non_neg_integer(), integer()) :: DataTx.t()
  def init(type, payload, senders, fee, nonce) when is_list(senders) do
    %DataTx{type: type, payload: type.init(payload), senders: senders, nonce: nonce, fee: fee}
  end

  def init(type, payload, sender, fee, nonce) when is_binary(sender) do
    %DataTx{type: type, payload: type.init(payload), senders: [sender], nonce: nonce, fee: fee}
  end

  def fee(%DataTx{fee: fee}) do fee end
  def senders(%DataTx{senders: senders}) do senders end
  def type(%DataTx{type: type}) do type end
  def nonce(%DataTx{nonce: nonce}) do nonce end
  def payload(%DataTx{payload: payload}) do payload end

  def sender(tx) do
    List.last(senders(tx))
  end

  @doc """
  Checks whether the fee is above 0. If it is, it runs the transaction type
  validation checks. Otherwise we return error.
  """
  @spec is_valid?(DataTx.t()) :: boolean()
  def is_valid?(%DataTx{fee: fee, type: type} = tx) do
    cond do
      !Enum.member?(valid_types(), type) ->
        Logger.error("Invalid tx type=#{type}")
        false

      fee < 0 ->
        Logger.error("Negative fee")
        false
      
      !is_payload_valid?(tx) ->
        false
      
      true ->
        true
    end
  end

  @doc """
  Changes the chainstate (account state and tx_type_state) according
  to the given transaction requirements
  """
  @spec process_chainstate!(ChainState.chainstate(), non_neg_integer(), DataTx.t()) ::
          ChainState.chainstate()
  def process_chainstate!(chainstate, block_height, %DataTx{fee: fee} = tx) do
    accounts_state = chainstate.accounts
    payload = tx.type.init(tx.payload)

    tx_type_state = Map.get(chainstate, tx.type.get_chain_state_name(), %{})

    :ok = tx.type.preprocess_check!(accounts_state, tx_type_state, block_height, payload, tx)
    
    nonce_accounts_state = if Enum.empty?(tx.senders) do
      accounts_state
    else
      MapUtil.update(accounts_state, sender(tx), Account.empty(), fn acc ->
        Account.apply_nonce!(acc, tx.nonce)
      end)
    end

    {new_accounts_state, new_tx_type_state} =
      nonce_accounts_state
      |> tx.type.deduct_fee(payload, tx, fee)
      |> tx.type.process_chainstate!(
        tx_type_state,
        block_height,
        payload,
        tx
      )

    if tx.type.get_chain_state_name() == nil do
      %{chainstate | accounts: new_accounts_state}
    else
      %{chainstate | accounts: new_accounts_state}
      |> Map.put(tx.type.get_chain_state_name(), new_tx_type_state)
    end
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

    init(data_tx.type, data_tx.payload, data_tx.senders, data_tx.fee, data_tx.nonce)
  end
 
  @spec standard_deduct_fee(ChainState.accounts(), DataTx.t(), non_neg_integer()) :: ChainState.account()
  def standard_deduct_fee(accounts, data_tx, fee) do
    sender = DataTx.sender(data_tx)
    MapUtil.update(accounts, sender, Account.empty(), fn acc ->
      Account.transaction_in!(acc, fee * -1)
    end)
  end

  defp is_payload_valid?(%DataTx{type: type, payload: payload} = data_tx) do
    payload
    |> type.init()
    |> type.is_valid?(data_tx)
  end 
end
