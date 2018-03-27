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
          to_acc: Wallet.pubkey(),
          value: non_neg_integer()
        }

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Structure that holds specific transaction info in the chainstate.
  In the case of SpendTx we don't have a subdomain chainstate."
  @type tx_type_state() :: %{}

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %SpendTx{
          to_acc: Wallet.pubkey(),
          value: non_neg_integer()
        }

  @doc """
  Definition of Aecore SpendTx structure

  ## Parameters
  - to_acc: To account is the public address of the account receiving the transaction
  - value: The amount of tokens send through the transaction
  """
  defstruct [:to_acc, :value]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: SpendTx.t()
  def init(%{to_acc: to_acc, value: value} = _payload) do
    %SpendTx{to_acc: to_acc, value: value}
  end

  @doc """
  Checks transactions internal contents validity
  """
  @spec is_valid?(SpendTx.t(), list(binary), integer()) :: boolean()
  def is_valid?(%SpendTx{value: value}, from_accs, fee) do
    cond do
      value < 0 ->
        Logger.error("Value cannot be a negative number")
        false

      fee <= 0 ->
        Logger.error("Fee has to be > 0")
        false

      length(from_accs) != 1 ->
        Logger.error("Invalid from_accs size")
        false

      true ->
        true
    end
  end

  @doc """
  Makes a rewarding SpendTx (coinbase tx) for the miner that mined the next block
  """
  @spec reward(SpendTx.t(), integer(), ChainState.account()) :: ChainState.accounts()
  def reward(%SpendTx{} = tx, _block_height, account_state) do
    Account.transaction_in(account_state, tx.value)
  end

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          ChainState.chainstate(),
          SpendTx.t(),
          list(binary()),
          non_neg_integer()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(chainstate, %SpendTx{} = tx, [from_acc], _fee) do
    new_from_account_state =
      chainstate.accounts[from_acc]
      |> Account.transaction_in(tx.value * -1)

    new_to_account_state =
      chainstate.accounts
      |> Map.get(tx.to_acc, Account.empty())
      |> Account.transaction_in(tx.value)

    new_accounts =
      chainstate.accounts
      |> Map.put(from_acc, new_from_account_state)
      |> Map.put(tx.to_acc, new_to_account_state)

    %{chainstate | accounts: new_accounts}
  end

  @doc """
  Checks whether all the data is valid according to the SpendTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          SpendTx.t(),
          ChainState.account(),
          list(binary()),
          non_neg_integer()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(tx, chainstate, [from_acc], fee) do
    if chainstate.accounts[from_acc].balance - (fee + tx.value) < 0 do
      {:error, "Negative balance"}
    else
      :ok
    end
  end

  @spec deduct_fee(ChainState.chainstate(), SpendTx.t(), list(binary()), non_neg_integer()) ::
          ChainState.account()
  def deduct_fee(chainstate, _tx, [from_acc], fee) do
    new_accounts =
      Map.update!(chainstate.accounts, from_acc, fn acc ->
        Account.transaction_in(acc, fee * -1)
      end)

    %{chainstate | accounts: new_accounts}
  end
end
