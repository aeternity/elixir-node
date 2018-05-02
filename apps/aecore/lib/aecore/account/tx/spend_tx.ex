defmodule Aecore.Account.Tx.SpendTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Tx.Transaction
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Account.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree

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

  # Callbacks

  @spec get_chain_state_name() :: :none
  def get_chain_state_name, do: :none

  @spec init(payload()) :: SpendTx.t()
  def init(%{receiver: receiver, amount: amount}) do
    %SpendTx{receiver: receiver, amount: amount, version: get_tx_version()}
  end

  @doc """
  Checks wether the amount that is send is not a negative number
  """
  @spec validate(SpendTx.t()) :: :ok | {:error, String.t()}
  def validate(%SpendTx{amount: amount, receiver: receiver}) do
    with true <- amount >= 0,
         :ok <- Wallet.key_size_valid?(receiver) do
      :ok
    else
      false ->
        {:error, "#{__MODULE__}: The amount cannot be a negative number: #{inspect(amount)}"}

      err ->
        err
    end
  end

  @doc """
  Makes a rewarding SpendTx (coinbase tx) for the miner that mined the next block
  """
  @spec reward(SpendTx.t(), Account.t()) :: Account.t()
  def reward(%SpendTx{} = tx, account_state) do
    Account.transaction_in(account_state, tx.amount)
  end

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate(
          SpendTx.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          AccountStateTree.tree(),
          tx_type_state()
        ) :: {AccountStateTree.tree(), tx_type_state()}
  def process_chainstate(%SpendTx{} = tx, sender, fee, nonce, _block_height, accounts, %{}) do
    sender_account_state = Account.get_account_state(accounts, sender)

    new_sender_account_state =
      sender_account_state
      |> deduct_fee(fee)
      |> Account.transaction_out(tx.amount * -1, nonce)

    new_accounts = AccountStateTree.put(accounts, sender, new_sender_account_state)
    receiver = Account.get_account_state(accounts, tx.receiver)
    new_receiver_acc_state = Account.transaction_in(receiver, tx.amount)

    {AccountStateTree.put(new_accounts, tx.receiver, new_receiver_acc_state), %{}}
  end

  @doc """
  Checks whether all the data is valid according to the SpendTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          SpendTx.t(),
          Wallet.pubkey(),
          Account.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          tx_type_state
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, _sender, account_state, fee, _nonce, _block_height, %{}) do
    if account_state.balance - (fee + tx.amount) >= 0 do
      :ok
    else
      {:error,
       "#{__MODULE__}: Negative balance: #{inspect(account_state.balance - (fee + tx.amount))}"}
    end
  end

  @spec deduct_fee(Account.t(), non_neg_integer()) :: Account.t()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  @spec is_minimum_fee_met?(SignedTx.t()) :: boolean()
  def is_minimum_fee_met?(tx) do
    tx.data.fee >= Application.get_env(:aecore, :tx_data)[:minimum_fee]
  end

  def get_tx_version, do: Application.get_env(:aecore, :spend_tx)[:version]
end
