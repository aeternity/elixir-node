defmodule Aecore.Structures.DataTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  alias Aecore.Structures.DataTx
  alias Aecore.Chain.ChainState
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Account
  alias Aeutil.Serialization
  alias Aeutil.Parser
  alias Aecore.Structures.Account

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
  @spec process_chainstate(DataTx.t(), ChainState.chainstate(), non_neg_integer()) ::
          ChainState.chainstate()
  def process_chainstate(%DataTx{} = tx, chainstate, block_height) do
    accounts_state = chainstate.accounts

    tx_type_state = get_tx_type_state(chainstate, tx.type)

    case tx.payload
         |> tx.type.init()
         |> tx.type.process_chainstate(
           tx.sender,
           tx.fee,
           tx.nonce,
           block_height,
           accounts_state,
           tx_type_state
         ) do
      {:error, reason} ->
        {:error, reason}

      {new_accounts_state, new_tx_type_state} ->
        new_chainstate =
          if tx.type == SpendTx do
            chainstate
          else
            Map.put(chainstate, tx.type.get_chain_state_name(), new_tx_type_state)
          end

        {:ok, Map.put(new_chainstate, :accounts, new_accounts_state)}
    end
  end

  @doc """
  Gets the given transaction type state,
  if there is any stored in the chainstate
  """
  @spec get_tx_type_state(ChainState.chainstate(), atom()) :: map()
  def get_tx_type_state(chainstate, tx_type) do
    type = tx_type.get_chain_state_name()
    Map.get(chainstate, type, %{})
  end

  @spec validate_sender(Wallet.pubkey(), ChainState.chainstate()) :: :ok | {:error, String.t()}
  def validate_sender(sender, chainstate) do
    if Map.has_key?(chainstate.accounts, sender) do
      :ok
    else
      {:error, "#{__MODULE__}: The senders key: #{inspect(sender)} doesn't exist"}
    end
  end

  @spec validate_nonce(ChainState.account(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate_nonce(accounts_state, tx) do
    account_state = Map.get(accounts_state, tx.sender, Account.empty())

    if tx.nonce > account_state.nonce do
      :ok
    else
      {:error, "#{__MODULE__}: Nonce is too small: #{inspect(tx.nonce)}"}
    end
  end

  @spec preprocess_check(DataTx.t(), ChainState.chain_state(), non_neg_integer()) ::
          :ok | {:error, String.t()}
  def preprocess_check(
        %DataTx{
          type: type,
          payload: payload,
          sender: sender,
          fee: fee
        } = tx,
        chainstate,
        block_height
      ) do
    sender_account_state = Map.get(chainstate.accounts, sender)
    tx_type_state = get_tx_type_state(chainstate, tx.type)
    type.preprocess_check(payload, sender, sender_account_state, fee, block_height, tx_type_state)
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
end
