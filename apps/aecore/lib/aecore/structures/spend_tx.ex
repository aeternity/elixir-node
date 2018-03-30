defmodule Aecore.Structures.SpendTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Structures.Transaction
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Account
  alias Aecore.Chain.ChainState
  alias Aecore.Wallet
  alias Aecore.Structures.Account

  require Logger

  @typedoc "Expected structure for the Spend Transaction"
  @type payload :: %{
          receiver: Wallet.pubkey(),
          amount: non_neg_integer(),
          version: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of SpendTx we don't have a subdomain chainstate."
  @type tx_type_state() :: %{}

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %SpendTx{
          receiver: Wallet.pubkey(),
          amount: non_neg_integer(),
          version: non_neg_integer()
        }

  @doc """
  Definition of Aecore SpendTx structure

  ## Parameters
  - receiver: To account is the public address of the account receiving the transaction
  - amount: The amount of tokens send through the transaction
  - version: States whats the version of the Spend Transaction
  """
  defstruct [:receiver, :amount, :version]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: SpendTx.t()
  def init(%{receiver: receiver, amount: amount}) do
    %SpendTx{receiver: receiver, amount: amount, version: get_tx_version()}
  end

  @doc """
  Checks wether the amount that is send is not a negative number
  """
  @spec is_valid?(SpendTx.t()) :: boolean()
  def is_valid?(%SpendTx{amount: amount}) do
    if amount >= 0 do
      true
    else
      Logger.error("The amount cannot be a negative number")
      false
    end
  end

  @doc """
  Makes a rewarding SpendTx (coinbase tx) for the miner that mined the next block
  """
  @spec reward(SpendTx.t(), integer(), ChainState.account()) :: ChainState.accounts()
  def reward(%SpendTx{} = tx, _block_height, account_state) do
    Account.transaction_in(account_state, tx.amount)
  end

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          SpendTx.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          ChainState.account(),
          tx_type_state()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(%SpendTx{} = tx, sender, fee, nonce, accounts, %{}) do
    sender_account_state = Map.get(accounts, sender, Account.empty())

    case preprocess_check(tx, sender_account_state, fee, %{}) do
      :ok ->
        new_sender_account_state =
          sender_account_state
          |> deduct_fee(fee)
          |> Account.transaction_out(tx.amount * -1, nonce)

        new_accounts = Map.put(accounts, sender, new_sender_account_state)

        receiver = Map.get(accounts, tx.receiver, Account.empty())
        new_receiver_acc_state = Account.transaction_in(receiver, tx.amount)
        {Map.put(new_accounts, tx.receiver, new_receiver_acc_state), %{}}

      {:error, _reason} = err ->
        throw(err)
    end
  end

  @doc """
  Checks whether all the data is valid according to the SpendTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          SpendTx.t(),
          ChainState.account(),
          non_neg_integer(),
          tx_type_state()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, account_state, fee, %{}) do
    cond do
      account_state.balance - (fee + tx.amount) < 0 ->
        {:error, "Negative balance"}

      true ->
        :ok
    end
  end

  @spec deduct_fee(ChainState.account(), non_neg_integer()) :: ChainState.account()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  def get_tx_version, do: Application.get_env(:aecore, :spend_tx)[:version]
end
