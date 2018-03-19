defmodule Aecore.Structures.Account do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  require Logger

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Account
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx

  @type t :: %Account{
          balance: non_neg_integer(),
          nonce: non_neg_integer()
        }

  @doc """
  Definition of Account structure

  ## Parameters
  - balance: The acccount balance
  - nonce: Out transaction count
  """
  defstruct [:balance, :nonce]
  use ExConstructor

  @spec empty() :: Account.t()
  def empty() do
    %Account{balance: 0, nonce: 0}
  end

  @doc """
  Builds a SpendTx where the miners public key is used as a sender (sender)
  """
  @spec spend(Wallet.pubkey(), non_neg_integer(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def spend(receiver, amount, fee) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Map.get(Chain.chain_state().accounts, sender, %{nonce: 0}).nonce + 1
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
    payload = %{receiver: receiver, amount: amount, lock_time_block: 0}
    spend_tx = DataTx.init(SpendTx, payload, sender, fee, nonce)
    SignedTx.sign_tx(spend_tx, sender_priv_key)
  end

  @doc """
  Adds balance to a given address (public key)
  """
  @spec transaction_in(ChainState.account(), integer()) :: ChainState.account()
  def transaction_in(account_state, amount) do
    new_balance = account_state.balance + amount
    Map.put(account_state, :balance, new_balance)
  end

  @doc """
  Deducts balance from a given address (public key)
  """
  @spec transaction_out(ChainState.account(), integer(), integer()) :: ChainState.account()
  def transaction_out(account_state, amount, nonce) do
    account_state
    |> Map.put(:nonce, nonce)
    |> transaction_in(amount)
  end
end
