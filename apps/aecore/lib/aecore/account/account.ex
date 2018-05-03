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
          last_updated: non_neg_integer()
        }

  @type account_payload :: %{
          balance: non_neg_integer(),
          nonce: non_neg_integer(),
          last_updated: non_neg_integer()
        }

  @type chain_state_name :: :accounts

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
          DataTx.paload(),
          DataTx.tx_types(),
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def build_tx(payload, tx_type, sender, sender_prv, fee, nonce) do
    tx = DataTx.init(tx_type, payload, sender, fee, nonce)
    SignedTx.sign_tx(tx, sender_prv)
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
    |> transaction_out_nonce_update(nonce)
    |> transaction_in(amount)
  end

  @spec transaction_out_nonce_update(ChainState.account(), integer()) :: ChainState.account()
  def transaction_out_nonce_update(account_state, nonce),
    do: Map.put(account_state, :nonce, nonce)

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
  @spec balance(AccountStateTree.tree(), Wallet.pubkey()) :: non_neg_integer()
  def balance(tree, key) do
    get_account_state(tree, key).balance
  end

  @doc """
  Return the nonce for a given key.
  """
  @spec nonce(AccountStateTree.tree(), Wallet.pubkey()) :: non_neg_integer()
  def nonce(tree, key) do
    get_account_state(tree, key).nonce
  end

  @doc """
  Return the last_updated for a given key.
  """
  @spec last_updated(AccountStateTree.tree(), Wallet.pubkey()) :: non_neg_integer()
  def last_updated(tree, key) do
    get_account_state(tree, key).last_updated
  end

  def last_updated(tree, key, block_height) do
    state = Account.get_account_state(tree, key)
    updated_state = %{state | last_updated: block_height}
    AccountStateTree.put(tree, key, updated_state)
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

  @spec rlp_encode(Account.t(), Wallet.pubkey()) :: binary()
  def rlp_encode(%Account{} = account, pkey) when is_binary(pkey) do
    [
      type_to_tag(Account),
      get_version(Account),
      # pubkey ,
      pkey,
      # nonce
      account.nonce,
      # height
      account.last_updated,
      # balance
      account.balance
    ]
    |> ExRLP.encode()
  end

  def rlp_encode(_) do
    {:error, :illegal_serialization}
  end

  def rlp_decode(values) when is_binary(values) do
    [tag_bin, ver_bin | rest_data] = ExRLP.decode(values)
    tag = Serialization.transform_item(tag_bin, :int)
    ver = Serialization.transform_item(ver_bin, :int)

    case tag_to_type(tag) do
      Account ->
        [pkey, nonce, height, balance] = rest_data

        [
          pkey,
          Serialization.transform_item(nonce, :int),
          Serialization.transform_item(height, :int),
          Serialization.transform_item(balance, :int)
        ]

        {:ok,
         %Account{
           balance: Serialization.transform_item(balance, :int),
           last_updated: Serialization.transform_item(height, :int),
           nonce: Serialization.transform_item(nonce, :int)
         }}

      _ ->
        {:error, :invalid_serialization}
    end
  end

  def rlp_decode(:none) do
    :none
  end

  def rlp_decode(_) do
    {:error, :illegal_serialization}
  end

  defp type_to_tag(Account), do: 10
  defp tag_to_type(10), do: Account
  defp get_version(Account), do: 1
end
