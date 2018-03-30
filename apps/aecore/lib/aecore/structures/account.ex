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
  alias Aecore.Structures.CoinbaseTx

  @type t :: %Account{
          balance: non_neg_integer(),
          nonce: non_neg_integer()
        }

  @doc """
  Definition of Account structure

  ## Parameters
  - nonce: Out transaction count
  - balance: The acccount balance
  """
  defstruct [:balance, :nonce]
  use ExConstructor

  @spec empty() :: Account.t()
  def empty() do
    %Account{balance: 0, nonce: 0}
  end

  @doc """
  Builds a SpendTx where the miners public key is used as a sender (from_acc)
  """
  @spec spend(Wallet.pubkey(), non_neg_integer(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def spend(to_acc, amount, fee) do
    from_acc = Wallet.get_public_key()
    from_acc_priv_key = Wallet.get_private_key()
    nonce = Map.get(Chain.chain_state().accounts, from_acc, %{nonce: 0}).nonce + 1
    spend(from_acc, from_acc_priv_key, to_acc, amount, fee, nonce)
  end

  @spec create_coinbase_tx(binary(), non_neg_integer()) :: SignedTx.t()
  def create_coinbase_tx(to_acc, value) do
    payload = CoinbaseTx.create(to_acc, value)
    data = DataTx.init(CoinbaseTx, payload, [], 0)
    SignedTx.create(data)
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
  def spend(from_acc, from_acc_priv_key, to_acc, amount, fee, nonce) do
    payload = %{to_acc: to_acc, value: amount}
    spend_tx = DataTx.init(SpendTx, payload, [from_acc], fee)
    SignedTx.sign_tx(spend_tx, nonce, from_acc_priv_key)
  end

  @doc """
  Adds balance to a given address (public key)
  """
  @spec transaction_in(ChainState.account(), integer()) :: ChainState.account()
  def transaction_in!(account_state, value) do
    new_balance = account_state.balance + value
    if new_balance < 0 do
      throw({:error, "Negative balance"})
    end

    %Account{account_state | balance: new_balance}
  end

  @spec apply_nonce!(ChainState.account(), integer()) :: ChainState.account()
  def apply_nonce!(%Account{nonce: current_nonce} = account_state, new_nonce) do
    if current_nonce >= new_nonce do
      throw({:error, "Invalid nonce"})
    end

    %Account{account_state | nonce: new_nonce}
  end
end
