defmodule Aecore.Account.Tx.CoinbaseTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Tx.Transaction

  alias Aecore.Tx.DataTx
  alias Aecore.Account.Tx.CoinbaseTx
  alias Aecore.Account.Account
  alias Aecore.Chain.ChainState
  alias Aecore.Wallet.Worker, as: Wallet
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

  def get_chain_state_name, do: nil

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
  @spec validate(CoinbaseTx.t(), DataTx.t()) :: :ok | {:error, String.t()}
  def validate(%CoinbaseTx{amount: amount, receiver: receiver}, data_tx) do
    senders = DataTx.senders(data_tx)

    cond do
      amount < 0 ->
        {:error, "Value cannot be a negative number"}

      DataTx.fee(data_tx) != 0 ->
        {:error, "Fee has to be 0"}

      !Wallet.key_size_valid?(receiver) ->
        {:error, "Wrong receiver key size"}

      !Enum.empty?(senders) ->
        {:error, "Invalid senders size"}

      true ->
        :ok
    end
  end

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate(
          ChainState.accounts(),
          tx_type_state(),
          non_neg_integer(),
          CoinbaseTx.t(),
          DataTx.t()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate(accounts, %{}, block_height, %CoinbaseTx{} = tx, _data_tx) do
    new_accounts_state =
      accounts
      |> AccountStateTree.update(tx.receiver, fn acc ->
        Account.apply_transfer!(acc, block_height, tx.amount)
      end)

    {:ok, {new_accounts_state, %{}}}
  end

  def process_chainstate(_accounts, %{}, _block_height, _tx, _data_tx) do
    {:error, "Invalid coinbase tx"}
  end

  @doc """
  Checks whether all the data is valid according to the CoinbaseTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          ChainState.accounts(),
          tx_type_state(),
          non_neg_integer(),
          CoinbaseTx.t(),
          DataTx.t()
        ) :: :ok
  def preprocess_check(_accounts, %{}, _block_height, _tx, _data_tx) do
    :ok
  end

  @spec deduct_fee(
          ChainState.accounts(),
          non_neg_integer(),
          CoinbaseTx.t(),
          DataTx.t(),
          non_neg_integer()
        ) :: ChainState.accounts()
  def deduct_fee(accounts, _block_height, _tx, _data_tx, _fee) do
    accounts
  end
end
