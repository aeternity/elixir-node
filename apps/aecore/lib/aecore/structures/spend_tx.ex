defmodule Aecore.Structures.SpendTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Structures.Transaction
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Account
  alias Aecore.Wallet
  alias Aecore.Structures.Account
  alias Aecore.Structures.Chainstate
  alias Aecore.Structures.AccountStateTree
  alias Aecore.Txs.Pool.Worker, as: Pool

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
  @spec reward(SpendTx.t(), Account.t()) :: Account.t()
  def reward(%SpendTx{} = tx, account_state) do
    Account.transaction_in(account_state, tx.amount)
  end

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          SpendTx.t(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          AccountStateTree.tree(),
          tx_type_state()
        ) :: {AccountStateTree.tree(), tx_type_state()} | {:error, String.t()}
  def process_chainstate!(%SpendTx{} = tx, sender, fee, nonce, block_height, accounts, %{}) do
    sender_account_state = Account.get_account_state(accounts, sender)

    case preprocess_check!(tx, sender, sender_account_state, fee, block_height, nonce, %{}) do
      :ok ->
        new_sender_account_state =
          sender_account_state
          |> deduct_fee(fee)
          |> Account.transaction_out(tx.amount * -1, nonce)

        new_accounts = AccountStateTree.put(accounts, sender, new_sender_account_state)
        receiver = Account.get_account_state(accounts, tx.receiver)
        new_receiver_acc_state = Account.transaction_in(receiver, tx.amount)

        {AccountStateTree.put(new_accounts, tx.receiver, new_receiver_acc_state), %{}}

      {:error, _reason} = err ->
        throw(err)
    end
  end

  @doc """
  Checks whether all the data is valid according to the SpendTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check!(
          SpendTx.t(),
          Wallet.pubkey(),
          AccountStateTree.tree(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          tx_type_state
        ) :: :ok | {:error, String.t()}
  def preprocess_check!(tx, _sender, sender_account_state, fee, _block_height, _nonce, %{}) do
    cond do
      sender_account_state.balance - (fee + tx.amount) < 0 ->
        throw({:error, "Negative balance"})

      true ->
        :ok
    end
  end

  @spec deduct_fee(Chainstate.accounts_state(), non_neg_integer()) :: Account.t()
  def deduct_fee(account_state, fee) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  @spec is_minimum_fee_met?(SignedTx.t(), :miner | :pool | :validation) :: boolean()
  def is_minimum_fee_met?(tx, identifier) do
    if identifier == :validation do
      true
    else
      tx_size_bytes = Pool.get_tx_size_bytes(tx)

      bytes_per_token =
        case identifier do
          :pool ->
            Application.get_env(:aecore, :tx_data)[:pool_fee_bytes_per_token]

          :miner ->
            Application.get_env(:aecore, :tx_data)[:miner_fee_bytes_per_token]
        end

      tx.data.fee >= Float.floor(tx_size_bytes / bytes_per_token)
    end
  end

  def get_tx_version, do: Application.get_env(:aecore, :spend_tx)[:version]
end
