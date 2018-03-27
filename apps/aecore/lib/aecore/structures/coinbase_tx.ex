defmodule Aecore.Structures.CoinbaseTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Structures.Transaction
  alias Aecore.Structures.CoinbaseTx
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

  @typedoc "Structure of the Coinbase Transaction type"
  @type t :: %CoinbaseTx{
          to_acc: Wallet.pubkey(),
          value: non_neg_integer()
        }

  @doc """
  Definition of Aecore CoinbaseTx structure

  ## Parameters
  - to_acc: To account is the public address of the account receiving the transaction
  - value: The amount of tokens send through the transaction
  """
  defstruct [:to_acc, :value]
  use ExConstructor

  # Callbacks

  @spec init(payload()) :: CoinbaseTx.t()
  def init(%{to_acc: to_acc, value: value} = _payload) do
    %CoinbaseTx{to_acc: to_acc, value: value}
  end

  @doc """
  Creates a rewarding CoinbaseTx for the miner that mined the block
  """
  @spec create(binary(), integer()) :: payload()
  def create(to_acc, value) do
    %CoinbaseTx{to_acc: to_acc, value: value}
  end

  @doc """
  Checks transactions internal contents validity
  """
  @spec is_valid?(CoinbaseTx.t(), list(binary()), non_neg_integer()) :: boolean()
  def is_valid?(%CoinbaseTx{value: value}, from_accs, fee) do
    cond do
      value < 0 ->
        Logger.error("Value cannot be a negative number")
        false

      fee != 0 ->
        Logger.error("Fee has to be 0")
        false

      length(from_accs) != 0 ->
        Logger.error("Invalid from_accs size")
        false

      true ->
        true
    end
  end

  @doc """
  Changes the account state (balance) of the sender and receiver.
  """
  @spec process_chainstate!(
          ChainState.chainstate(),
          CoinbaseTx.t(),
          list(binary()),
          non_neg_integer()
        ) :: {ChainState.accounts(), tx_type_state()}
  def process_chainstate!(chainstate, %CoinbaseTx{} = tx, [], 0) do
    new_to_account_state =
      chainstate.accounts
      |> Map.get(tx.to_acc, Account.empty())
      |> Account.transaction_in(tx.value)

    new_chainstate_accounts =
      chainstate.accounts
      |> Map.put(tx.to_acc, new_to_account_state)

    %{chainstate | accounts: new_chainstate_accounts}
  end

  def process_chainstate!(_chainstate, _tx, _from_accs, _fee) do
    throw({:error, "Invalid coinbase tx"})
  end

  @doc """
  Checks whether all the data is valid according to the CoinbaseTx requirements,
  before the transaction is executed.
  """
  @spec preprocess_check(
          CoinbaseTx.t(),
          Chainstate.chainstate(),
          list(binary()),
          non_neg_integer()
        ) :: :ok | {:error, String.t()}
  def preprocess_check(_tx, _chainstate, _from_accs, _fee) do
    :ok
  end

  def deduct_fee(chainstate, _tx, _from_acc, _fee) do
    chainstate
  end
end
