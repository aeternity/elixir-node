defmodule Aecore.Account.Account do
  @moduledoc """
  Aecore structure of a transaction data.
  """

  require Logger

  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Account.Account
  alias Aeutil.Bits
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Account.AccountStateTree
  alias Aecore.Account.Tx.CoinbaseTx

  @type t :: %Account{
          balance: non_neg_integer(),
          nonce: non_neg_integer(),
          last_updated: non_neg_integer()
        }

  @type account_payload :: %{
          balance: non_neg_integer(),
          nonce: non_neg_integer(),
          last_updated: non_neg_integer()
        }

  @doc """
  Definition of Account structure

  ## Parameters
  - balance: The acccount balance
  - nonce: Out transaction count
  """
  defstruct [:balance, :nonce, :last_updated]

  def empty, do: %Account{balance: 0, nonce: 0, last_updated: 0}

  @spec new(account_payload()) :: Account.t()
  def new(%{balance: balance, nonce: nonce, last_updated: last_updated}) do
    %Account{
      balance: balance,
      nonce: nonce,
      last_updated: last_updated
    }
  end

  @doc """
  Return the balance for a given key.
  """
  @spec balance(AccountStateTree.tree(), Wallet.pubkey()) :: non_neg_integer()
  def balance(tree, key) do
    AccountStateTree.get(tree, key).balance
  end

  @doc """
  Return the nonce for a given key.
  """
  @spec nonce(AccountStateTree.tree(), Wallet.pubkey()) :: non_neg_integer()
  def nonce(tree, key) do
    AccountStateTree.get(tree, key).nonce
  end

  @doc """
  Return the last_updated for a given key.
  """
  @spec last_updated(AccountStateTree.tree(), Wallet.pubkey()) :: non_neg_integer()
  def last_updated(tree, key) do
    AccountStateTree.get(tree, key).last_updated
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

  @spec create_coinbase_tx(binary(), non_neg_integer()) :: SignedTx.t()
  def create_coinbase_tx(to_acc, value) do
    payload = CoinbaseTx.create(to_acc, value)
    data = DataTx.init(CoinbaseTx, payload, [], 0, 0)
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
  def spend(sender, sender_priv_key, receiver, amount, fee, nonce) do
    payload = %{receiver: receiver, amount: amount}
    spend_tx = DataTx.init(SpendTx, payload, [sender], fee, nonce)
    SignedTx.sign_tx(spend_tx, sender, sender_priv_key)
  end

  @doc """
  Adds balance to a given Account state and updates last update block.
  """
  @spec apply_transfer!(ChainState.account(), non_neg_integer(), integer()) ::
          ChainState.account()
  def apply_transfer!(account_state, block_height, amount) do
    new_balance = account_state.balance + amount

    if new_balance < 0 do
      throw({:error, "Negative balance"})
    end

    %Account{account_state | balance: new_balance, last_updated: block_height}
  end

  @spec apply_nonce!(ChainState.account(), integer()) :: ChainState.account()
  def apply_nonce!(%Account{nonce: current_nonce} = account_state, new_nonce) do
    if current_nonce >= new_nonce do
      throw({:error, "Invalid nonce"})
    end

    %Account{account_state | nonce: new_nonce}
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

  def base58c_decode(bin) do
    {:error, "#{__MODULE__}: Wrong data: #{inspect(bin)}"}
  end
end
