defmodule Aecore.Structures.SpendTx do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  @behaviour Aecore.Structures.Transaction

  alias Aeutil.Serialization
  alias Aeutil.Parser
  alias Aecore.Structures.Account

  @typedoc "Arbitrary structure data of a transaction"
  @type payload :: %__MODULE__{} | map()

  @typedoc "Reason for the error"
  @type reason :: String.t()

  @typedoc "Public key of the account"
  @type pub_key() :: binary()

  @typedoc "Structure that holds specific transaction info in the chainstate"
  @type subdomain_chainstate() :: map()

  @typedoc "Structure that holds the account info"
  @type account_state :: %{pub_key() => Account.t()}

  @typedoc "Structure of the Spend Transaction type"
  @type t :: %__MODULE__{
    to_acc: binary(),
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
  def init(%{to_acc: to_acc, value: value} = payload) do
    %__MODULE__{to_acc: to_acc,
                value: value}
  end

  @spec is_valid(SpendTx.t()) :: :ok | {:error, reason()}
  def is_valid(%__MODULE__{value: value}) do
    if value >= 0 do
      :ok
    else
      {:error, "Value cannot be a negative number"}
    end
  end

  @spec reward(SpendTx.t(), integer(), account_state()) :: account_state()
  def reward(%__MODULE__{} = tx, block_height, account_state) do
    transaction_in(account_state, tx.value)
  end

  @spec process_chainstate!(SpendTx.t(), binary(), non_neg_integer(), non_neg_integer(),
    non_neg_integer(), account_state(), subdomain_chainstate()) ::
  {account_state(), subdomain_chainstate()}
  def process_chainstate!(%__MODULE__{} = tx, from_acc, fee, nonce, block_height,
                          accounts, %{}) do
    case preprocess_check(tx, accounts[from_acc], fee, nonce, block_height, %{}) do
      :ok ->
        new_from_account_state =
          accounts[from_acc]
          |> deduct_fee(fee, nonce)
          |> transaction_out(tx.value * -1, nonce)
        new_accounts = Map.put(accounts, from_acc, new_from_account_state)

        to_acc = Map.get(accounts, tx.to_acc, Account.empty())
        new_to_account_state =
          transaction_in(to_acc, tx.value)
        Map.put(new_accounts, tx.to_acc, new_to_account_state)

      {:error, reason} = err ->
        throw err
    end
  end

  def preprocess_check(tx, account_state, fee, nonce, block_height, %{}) do
    cond do
      account_state.balance - (fee + tx.value) < 0 ->
       {:error, "Negative balance"}

      account_state.nonce >= nonce ->
       {:error, "Nonce too small"}

      true ->
        :ok
    end
  end

  def deduct_fee(account_state, fee, nonce) do
    new_balance = account_state.balance - fee
    Map.put(account_state, :balance, new_balance)
  end

  # Inner functions

  @spec transaction_in(account_state(), integer()) :: account_state()
  defp transaction_in(account_state, value) do
      new_balance = account_state.balance + value
      Map.put(account_state, :balance, new_balance)
  end

  @spec transaction_out(account_state(), integer(), integer()) :: account_state()
  defp transaction_out(account_state, value, nonce) do
    account_state
    |> Map.put(:nonce, nonce)
    |> transaction_in(value)
  end
end
