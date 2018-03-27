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
  alias Aecore.Naming.Structures.PreClaimTx
  alias Aecore.Naming.Structures.ClaimTx
  alias Aecore.Naming.Structures.UpdateTx
  alias Aecore.Naming.Structures.Naming
  alias Aecore.Naming.Util

  @type t :: %Account{
          balance: non_neg_integer(),
          nonce: non_neg_integer()
        }

  @type chain_state_name :: :accounts

  @doc """
  Definition of Account structure

  ## Parameters
  - balance: The acccount balance
  - nonce: Out transaction count
  """
  defstruct [:balance, :nonce]
  use ExConstructor

  def empty, do: %Account{balance: 0, nonce: 0}

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
  Builds a PreClaimTx where the miners public key is used as a sender
  """
  @spec pre_claim(String.t(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def pre_claim(name, fee) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Map.get(Chain.chain_state().accounts, sender, %{nonce: 0}).nonce + 1
    name_salt = <<1, 2, 3>>
    pre_claim(sender, sender_priv_key, name, name_salt, fee, nonce)
  end

  @doc """
  Build a PreClaimTx from the given sender keys
  """
  @spec pre_claim(
          Wallet.pubkey(),
          Wallet.privkey(),
          String.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()}
  def pre_claim(sender, sender_priv_key, name, name_salt, fee, nonce) do
    payload = %{commitment: Naming.create_commitment_hash(name, name_salt)}
    spend_tx = DataTx.init(PreClaimTx, payload, sender, fee, nonce)
    SignedTx.sign_tx(spend_tx, sender_priv_key)
  end

  @doc """
  Builds a ClaimTx where the miners public key is used as a sender
  """
  @spec claim(String.t(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def claim(name, fee) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Map.get(Chain.chain_state().accounts, sender, %{nonce: 0}).nonce + 1
    name_salt = <<1, 2, 3>>
    claim(sender, sender_priv_key, name, name_salt, fee, nonce)
  end

  @doc """
  Build a ClaimTx from the given sender keys
  """
  @spec claim(
          Wallet.pubkey(),
          Wallet.privkey(),
          String.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()}
  def claim(sender, sender_priv_key, name, name_salt, fee, nonce) do
    payload = %{name: name, name_salt: name_salt}
    spend_tx = DataTx.init(ClaimTx, payload, sender, fee, nonce)
    SignedTx.sign_tx(spend_tx, sender_priv_key)
  end

  @doc """
  Builds a ClaimTx where the miners public key is used as a sender
  """
  @spec name_update(String.t(), String.t(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def name_update(name, pointers, fee) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Map.get(Chain.chain_state().accounts, sender, %{nonce: 0}).nonce + 1
    name_update(sender, sender_priv_key, name, pointers, fee, nonce)
  end

  @doc """
  Build a ClaimTx from the given sender keys
  """
  @spec name_update(
          Wallet.pubkey(),
          Wallet.privkey(),
          String.t(),
          String.t(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()}
  def name_update(sender, sender_priv_key, name, pointers, fee, nonce) do
    payload = %{
      hash: Util.normalized_hash!(name),
      expire_by: Chain.top_height() + Naming.get_claim_expire_by_relative_limit(),
      client_ttl: 86400,
      pointers: pointers
    }

    spend_tx = DataTx.init(UpdateTx, payload, sender, fee, nonce)
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
    |> transaction_out_nonce_update(nonce)
    |> transaction_in(amount)
  end

  @spec transaction_out_nonce_update(ChainState.account(), integer()) :: ChainState.account()
  def transaction_out_nonce_update(account_state, nonce) do
    account_state
    |> Map.put(:nonce, nonce)
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
