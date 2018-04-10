defmodule Aecore.Structures.Account do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  require Logger

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Account
  alias Aeutil.Bits
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.AccountStateTree

  @type t :: %Account{
          balance: non_neg_integer(),
          nonce: non_neg_integer()
        }

  @type account_payload :: %{balance: non_neg_integer(), nonce: non_neg_integer()}

  @doc """
  Definition of Account structure

  ## Parameters
  - balance: The acccount balance
  - nonce: Out transaction count
  """
  defstruct [:balance, :nonce]

  def empty, do: %Account{balance: 0, nonce: 0}

  @spec new(account_payload()) :: Account.t()
  def new(%{balance: balance, nonce: nonce}) do
    %Account{
      balance: balance,
      nonce: nonce
    }
  end

  @doc """
  Builds a SpendTx where the miners public key is used as a sender (sender)
  """
  @spec spend(Wallet.pubkey(), non_neg_integer(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def spend(receiver, amount, fee) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    spend(sender, sender_priv_key, receiver, amount, fee, nonce)
  end

  @doc """
  Build a SpendTx from the given sender keys to the receivers account
  """
  @spec spend(
          Wallet.pubkey(),
          Wallet.privkey(),
          Wallet.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()}
  def spend(sender, sender_priv_key, receiver, amount, fee, nonce) do
    payload = %{receiver: receiver, amount: amount}
    spend_tx = DataTx.init(SpendTx, payload, sender, fee, nonce)
    SignedTx.sign_tx(spend_tx, sender_priv_key)
  end

  @doc """
  Adds balance to a given address (public key)
  """
  @spec transaction_in(Account.t(), integer()) :: Account.t()
  def transaction_in(account_state, amount) do
    new_balance = account_state.balance + amount
    Map.put(account_state, :balance, new_balance)
  end

  @doc """
  Deducts balance from a given address (public key)
  """
  @spec transaction_out(Account.t(), integer(), integer()) :: Account.t()
  def transaction_out(account_state, amount, nonce) do
    account_state
    |> Map.put(:nonce, nonce)
    |> transaction_in(amount)
  end

  @spec get_account_state(AccountStateTree.tree(), Wallet.pubkey()) :: Account.t()
  def get_account_state(tree, key) do
    case AccountStateTree.get(tree, key) do
      :none ->
        empty()

      {:ok, account_state} ->
        account_state
    end
  end

  @doc """
  Return the balance for a given key.
  """
  @spec balance(AccountStateTree.tree(), Wallet.pubkey()) :: integer()
  def balance(tree, key) do
    get_account_state(tree, key).balance
  end

  @doc """
  Return the nonce for a given key.
  """
  @spec nonce(AccountStateTree.tree(), Wallet.pubkey()) :: integer()
  def nonce(tree, key) do
    get_account_state(tree, key).nonce
  end

  def base58c_encode(bin) do
    if bin == nil do
      nil
    else
      Bits.encode58c("ak", bin)
    end
  end

  def base58c_decode(<<"ak$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "Wrong data"}
  end
end
