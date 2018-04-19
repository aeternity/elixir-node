defmodule Aecore.Structures.CoinbaseTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Tx.DataTx
  alias Aecore.Structures.CoinbaseTx
  alias Aecore.Account.Account
  alias Aecore.Chain.ChainState
  alias Aecore.Wallet
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree

  require Logger

  @typedoc "Expected structure for the Spend Transaction"
  @type payload :: %{
          receiver: Wallet.pubkey(),
          amount: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of SpendTx we don't have a subdomain chainstate."
  @type tx_type_state() :: %{}

  @typedoc "Structure of the Coinbase Transaction type"
  @type t :: %CoinbaseTx{
          receiver: Wallet.pubkey(),
          amount: non_neg_integer()
        }

  @doc """
  Definition of Aecore CoinbaseTx structure

  ## Parameters
  - receiver: To account is the public address of the account receiving coinbase tokens
  - amount: The amount of tokens account should be granted
  """
  defstruct [:receiver, :amount]
  use ExConstructor

  # Callbacks

  def get_chain_state_name() do
    nil
  end

  @spec init(payload()) :: CoinbaseTx.t()
  def init(%{receiver: receiver, amount: amount} = _payload) do
    %CoinbaseTx{receiver: receiver, amount: amount}
  end

  @doc """
  Creates a rewarding CoinbaseTx for the miner that mined the block
  """
  @spec create(binary(), integer()) :: payload()
  def create(receiver, amount) do
    %CoinbaseTx{receiver: receiver, amount: amount}
  end

  @doc """
  Checks transactions internal contents validity
  """
  @spec is_valid?(CoinbaseTx.t(), DataTx.t()) :: boolean()
  def is_valid?(%CoinbaseTx{amount: amount}, data_tx) do
    cond do
      amount < 0 ->
        Logger.error("Value cannot be a negative number")
        false

      DataTx.fee(data_tx) != 0 ->
        Logger.error("Fee has to be 0")
        false

      length(DataTx.senders(data_tx)) != 0 ->
        Logger.error("Invalid senders size")
        false

      true ->
        true
    end
  end

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          ChainState.accounts(),
          tx_type_state(),
          non_neg_integer(),
          CoinbaseTx.t(),
          DataTx.t()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(accounts, %{}, _block_height, %CoinbaseTx{} = tx, _data_tx) do
    new_accounts_state =
      accounts
      |> AccountStateTree.update(tx.receiver, fn acc ->
        Account.transaction_in!(acc, tx.amount)
      end)

    {new_accounts_state, %{}}
  end

  def process_chainstate!(_accounts, %{}, _block_height, _tx, _data_tx) do
    throw({:error, "Invalid coinbase tx"})
  end

  @doc """
  Checks whether all the data is valid according to the CoinbaseTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check!(
          ChainState.accounts(),
          tx_type_state(),
          non_neg_integer(),
          CoinbaseTx.t(),
          DataTx.t()
        ) :: :ok
  def preprocess_check!(_accounts, %{}, _block_height, _tx, _data_tx) do
    :ok
  end

  @spec deduct_fee(ChainState.accounts(), CoinbaseTx.t(), DataTx.t(), non_neg_integer()) ::
          ChainState.accounts()
  def deduct_fee(accounts, _tx, _data_tx, _fee) do
    accounts
  end
end
