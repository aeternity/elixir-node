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
  alias Aecore.Naming.Tx.NamePreClaimTx
  alias Aecore.Naming.Tx.NameClaimTx
  alias Aecore.Naming.Tx.NameUpdateTx
  alias Aecore.Naming.Tx.NameTransferTx
  alias Aecore.Naming.Tx.NameRevokeTx
  alias Aecore.Naming.Naming
  alias Aecore.Naming.NameUtil
  alias Aecore.Account.AccountStateTree
  alias Aeutil.Serialization

  @type t :: %Account{
          balance: non_neg_integer(),
          nonce: non_neg_integer(),
          last_updated: non_neg_integer(),
          pubkey: Wallet.pubkey()
        }

  @type account_payload :: %{
          balance: non_neg_integer(),
          nonce: non_neg_integer(),
          last_updated: non_neg_integer(),
          pubkey: Wallet.pubkey()
        }

  @type chain_state_name :: :accounts

  @doc """
  Definition of Account structure

  ## Parameters
  - balance: The acccount balance
  - nonce: Out transaction count
  """
  defstruct [:balance, :nonce, :last_updated, :pubkey]

  def empty, do: %Account{balance: 0, nonce: 0, last_updated: 0, pubkey: <<>>}

  @spec new(account_payload()) :: Account.t()
  def new(%{balance: balance, nonce: nonce, last_updated: last_updated, pubkey: pubkey}) do
    %Account{
      balance: balance,
      nonce: nonce,
      last_updated: last_updated,
      pubkey: pubkey
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
  @spec spend(Wallet.pubkey(), non_neg_integer(), non_neg_integer(), binary()) ::
          {:ok, SignedTx.t()}
  def spend(receiver, amount, fee, payload) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    spend(sender, sender_priv_key, receiver, amount, fee, nonce, payload)
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
          non_neg_integer(),
          binary()
        ) :: {:ok, SignedTx.t()}
  def spend(sender, sender_priv_key, receiver, amount, fee, nonce, pl) do
    payload = %{
      receiver: receiver,
      amount: amount,
      payload: pl,
      version: SpendTx.get_tx_version()
    }

    build_tx(payload, SpendTx, sender, sender_priv_key, fee, nonce)
  end

  @doc """
  Builds a NamePreClaimTx where the miners public key is used as a sender
  """
  @spec pre_claim(String.t(), binary(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def pre_claim(name, name_salt, fee) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    pre_claim(sender, sender_priv_key, name, name_salt, fee, nonce)
  end

  @doc """
  Build a NamePreClaimTx from the given sender keys
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
    case Naming.create_commitment_hash(name, name_salt) do
      {:ok, commitment} ->
        payload = %{commitment: commitment}
        build_tx(payload, NamePreClaimTx, sender, sender_priv_key, fee, nonce)

      err ->
        err
    end
  end

  @doc """
  Builds a NameClaimTx where the miners public key is used as a sender
  """
  @spec claim(String.t(), binary(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def claim(name, name_salt, fee) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    claim(sender, sender_priv_key, name, name_salt, fee, nonce)
  end

  @doc """
  Build a NameClaimTx from the given sender keys
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
    case NameUtil.normalized_namehash(name) do
      {:ok, _} ->
        payload = %{name: name, name_salt: name_salt}
        build_tx(payload, NameClaimTx, sender, sender_priv_key, fee, nonce)

      err ->
        err
    end
  end

  @doc """
  Builds a NameUpdateTx where the miners public key is used as a sender
  """
  @spec name_update(String.t(), String.t(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def name_update(name, pointers, fee) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    name_update(sender, sender_priv_key, name, pointers, fee, nonce)
  end

  @doc """
  Build a NameUpdateTx from the given sender keys
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
    case NameUtil.normalized_namehash(name) do
      {:ok, namehash} ->
        payload = %{
          hash: namehash,
          expire_by: Chain.top_height() + Naming.get_claim_expire_by_relative_limit(),
          client_ttl: 86400,
          pointers: pointers
        }

        build_tx(payload, NameUpdateTx, sender, sender_priv_key, fee, nonce)

      err ->
        err
    end
  end

  @doc """
  Builds a NameTransferTx where the miners public key is used as a sender
  """
  @spec name_transfer(String.t(), binary(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def name_transfer(name, target, fee) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    name_transfer(sender, sender_priv_key, name, target, fee, nonce)
  end

  @doc """
  Build a NameTransferTx from the given sender keys
  """
  @spec name_transfer(
          Wallet.pubkey(),
          Wallet.privkey(),
          String.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()}
  def name_transfer(sender, sender_priv_key, name, target, fee, nonce) do
    case NameUtil.normalized_namehash(name) do
      {:ok, namehash} ->
        payload = %{hash: namehash, target: target}
        build_tx(payload, NameTransferTx, sender, sender_priv_key, fee, nonce)

      err ->
        err
    end
  end

  @doc """
  Builds a NameTransferTx where the miners public key is used as a sender
  """
  @spec name_revoke(String.t(), non_neg_integer()) :: {:ok, SignedTx.t()}
  def name_revoke(name, fee) do
    sender = Wallet.get_public_key()
    sender_priv_key = Wallet.get_private_key()
    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    name_revoke(sender, sender_priv_key, name, fee, nonce)
  end

  @doc """
  Build a NameRevokeTx from the given sender keys
  """
  @spec name_revoke(
          Wallet.pubkey(),
          Wallet.privkey(),
          String.t(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()}
  def name_revoke(sender, sender_priv_key, name, fee, nonce) do
    case NameUtil.normalized_namehash(name) do
      {:ok, namehash} ->
        payload = %{hash: namehash}
        build_tx(payload, NameRevokeTx, sender, sender_priv_key, fee, nonce)

      err ->
        err
    end
  end

  @spec build_tx(
          DataTx.payload(),
          DataTx.tx_types(),
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def build_tx(payload, tx_type, sender, sender_prv, fee, nonce) do
    tx = DataTx.init(tx_type, payload, sender, fee, nonce)
    SignedTx.sign_tx(tx, sender, sender_prv)
  end

  @doc """
  Adds balance to a given Account state and updates last update block.
  """
  @spec apply_transfer!(ChainState.account(), non_neg_integer(), integer()) ::
          ChainState.account()
  def apply_transfer!(account_state, block_height, amount) do
    new_balance = account_state.balance + amount

    if new_balance < 0 do
      throw({:error, "#{__MODULE__}: Negative balance"})
    end

    %Account{account_state | balance: new_balance, last_updated: block_height}
  end

  @spec apply_nonce!(ChainState.account(), integer()) :: ChainState.account()
  def apply_nonce!(%Account{nonce: current_nonce} = account_state, new_nonce) do
    if current_nonce >= new_nonce do
      throw({:error, "#{__MODULE__}: Invalid nonce"})
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

  @spec rlp_encode(non_neg_integer(), non_neg_integer(), Account.t()) ::
          binary() | {:error, String.t()}
  def rlp_encode(tag, version, %Account{} = account) do
    list = [
      tag,
      version,
      account.pubkey,
      account.nonce,
      account.last_updated,
      account.balance
    ]

    try do
      ExRLP.encode(list)
    rescue
      e -> {:error, "#{__MODULE__}: " <> Exception.message(e)}
    end
  end

  def rlp_encode(data) do
    {:error, "#{__MODULE__}: Invalid Account structure: #{inspect(data)}"}
  end

  @spec rlp_decode(list()) :: {:ok, Account.t()} | {:error, String.t()}
  def rlp_decode([pubkey, nonce, height, balance]) do
    {:ok,
     %Account{
       pubkey: pubkey,
       balance: Serialization.transform_item(balance, :int),
       last_updated: Serialization.transform_item(height, :int),
       nonce: Serialization.transform_item(nonce, :int)
     }}
  end

  def rlp_decode(data) do
    {:error, "#{__MODULE__}: Invalid Account serialization #{inspect(data)}"}
  end
end
