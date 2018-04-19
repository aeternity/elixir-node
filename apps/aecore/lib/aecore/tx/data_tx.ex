defmodule Aecore.Tx.DataTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  alias Aecore.Tx.DataTx
  alias Aecore.Account.Tx.SpendTx
  alias Aeutil.Serialization
  alias Aeutil.Parser
  alias Aeutil.Bits
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree

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
    case AccountStateTree.get(account, sender) do
      {:ok, _account_key} ->
        :ok

      :none ->
        {:error, "#{__MODULE__}: The senders key: #{inspect(sender)} doesn't exist"}
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
end
