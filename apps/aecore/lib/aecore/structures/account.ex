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
  alias Aecore.Structures.AccountHandler

  @type t :: %Account{
          balance: non_neg_integer(),
          nonce: non_neg_integer()
        }

  @type account_payload :: map()

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

  @spec new(account_payload()) :: Account.t()
  def new(%{} = acc_payload) do
    %Account{
      :balance => acc_payload["balance"],
      :nonce => acc_payload["nonce"]
    }
  end

  @doc """
  Builds a SpendTx where the miners public key is used as a sender (from_acc)
  """
  @spec spend(Wallet.pubkey(), non_neg_integer(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def spend(to_acc, amount, fee) do
    from_acc = Wallet.get_public_key()
    from_acc_priv_key = Wallet.get_private_key()

    nonce = AccountHandler.nonce(Chain.chain_state().accounts, from_acc) + 1
    spend(from_acc, from_acc_priv_key, to_acc, amount, fee, nonce)
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
    spend_tx = DataTx.init(SpendTx, payload, from_acc, fee, nonce)
    SignedTx.sign_tx(spend_tx, from_acc_priv_key)
  end

  @doc """
  Adds balance to a given address (public key)
  """
  @spec transaction_in(Account.t(), integer()) :: Account.t()
  def transaction_in(account_state, value) do
    new_balance = account_state.balance + value
    Map.put(account_state, :balance, new_balance)
  end

  @doc """
  Deducts balance from a given address (public key)
  """
  @spec transaction_out(Account.t(), integer(), integer()) :: Account.t()
  def transaction_out(account_state, value, nonce) do
    account_state
    |> Map.put(:nonce, nonce)
    |> transaction_in(value)
  end

  def base58c_encode(bin) do
    Bits.encode58c("ak", bin)
  end

  def base58c_decode(<<"ak$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "Wrong data"}
  end
end
