defmodule Aecore.Account.Account do
  @moduledoc """
  Module defining the state structure of a single account
  """

  require Logger
  alias Aecore.Keys
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.Identifier
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Naming.Tx.{NamePreClaimTx, NameClaimTx, NameUpdateTx, NameTransferTx, NameRevokeTx}
  alias Aecore.Naming.{NameCommitment, NameUtil}
  alias Aeutil.Serialization
  alias Aeutil.Bits

  @version 1

  @type t :: %Account{
          balance: non_neg_integer(),
          nonce: non_neg_integer(),
          id: Identifier.t()
        }

  @type account_payload :: %{
          balance: non_neg_integer(),
          nonce: non_neg_integer(),
          id: Identifier.t()
        }

  @type chain_state_name :: :accounts

  @doc """
  Definition of the Account structure

  # Parameters
  - balance: the acccount balance
  - nonce: an integer which is updated (always increased) whenever an outgoing transaction is made by the account
  - id: the account itself
  """
  defstruct [:balance, :nonce, :id]
  use ExConstructor
  use Aecore.Util.Serializable

  def empty, do: %Account{balance: 0, nonce: 0, id: %Identifier{type: :account}}

  @spec new(account_payload()) :: Account.t()
  def new(%{balance: balance, nonce: nonce, pubkey: pubkey}) do
    id = Identifier.create_identity(pubkey, :account)

    %Account{
      balance: balance,
      nonce: nonce,
      id: id
    }
  end

  @doc """
  Return the balance for a given key.
  """
  @spec balance(AccountStateTree.accounts_state(), Keys.pubkey()) :: non_neg_integer()
  def balance(tree, key) do
    AccountStateTree.get(tree, key).balance
  end

  @doc """
  Return the nonce for a given key.
  """
  @spec nonce(AccountStateTree.accounts_state(), Keys.pubkey()) :: non_neg_integer()
  def nonce(tree, key) do
    AccountStateTree.get(tree, key).nonce
  end

  @doc """
  Builds a SpendTx where the miners public key is used as a sender
  """
  @spec spend(Keys.pubkey(), non_neg_integer(), non_neg_integer(), binary(), non_neg_integer()) ::
          {:ok, SignedTx.t()} | {:error, String.t()}
  def spend(receiver, amount, fee, payload, ttl \\ 0) do
    {sender, sender_priv_key} = Keys.keypair(:sign)
    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    spend(sender, sender_priv_key, receiver, amount, fee, nonce, payload, ttl)
  end

  @doc """
  Builds a SpendTx from the given sender keys to the receivers account
  """
  @spec spend(
          Keys.pubkey(),
          Keys.sign_priv_key(),
          Keys.pubkey(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          binary(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def spend(sender, sender_priv_key, receiver, amount, fee, nonce, pl, ttl \\ 0) do
    payload = %{
      receiver: receiver,
      amount: amount,
      payload: pl,
      version: SpendTx.get_tx_version()
    }

    build_tx(payload, SpendTx, sender, sender_priv_key, fee, nonce, ttl)
  end

  @doc """
  Builds a NamePreClaimTx where the miners public key is used as a sender
  """
  @spec pre_claim(String.t(), binary(), non_neg_integer(), non_neg_integer()) ::
          {:ok, SignedTx.t()} | {:error, String.t()}
  def pre_claim(name, name_salt, fee, ttl \\ 0) do
    {sender, sender_priv_key} = Keys.keypair(:sign)

    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    pre_claim(sender, sender_priv_key, name, name_salt, fee, nonce, ttl)
  end

  @doc """
  Builds a NamePreClaimTx from the given sender keys
  """
  @spec pre_claim(
          Keys.pubkey(),
          Keys.sign_priv_key(),
          String.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def pre_claim(sender, sender_priv_key, name, name_salt, fee, nonce, ttl \\ 0) do
    case NameCommitment.commitment_hash(name, name_salt) do
      {:ok, commitment} ->
        payload = %{commitment: commitment}
        build_tx(payload, NamePreClaimTx, sender, sender_priv_key, fee, nonce, ttl)

      err ->
        err
    end
  end

  @doc """
  Builds a NameClaimTx where the miners public key is used as a sender
  """
  @spec claim(String.t(), binary(), non_neg_integer(), non_neg_integer()) ::
          {:ok, SignedTx.t()} | {:error, String.t()}
  def claim(name, name_salt, fee, ttl \\ 0) do
    {sender, sender_priv_key} = Keys.keypair(:sign)

    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    claim(sender, sender_priv_key, name, name_salt, fee, nonce, ttl)
  end

  @doc """
  Builds a NameClaimTx from the given sender keys
  """
  @spec claim(
          Keys.pubkey(),
          Keys.sign_priv_key(),
          String.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def claim(sender, sender_priv_key, name, name_salt, fee, nonce, ttl \\ 0) do
    case NameUtil.normalized_namehash(name) do
      {:ok, _} ->
        payload = %{name: name, name_salt: name_salt}
        build_tx(payload, NameClaimTx, sender, sender_priv_key, fee, nonce, ttl)

      err ->
        err
    end
  end

  @doc """
  Builds a NameUpdateTx where the miners public key is used as a sender
  """
  @spec name_update(
          String.t(),
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def name_update(name, pointers, fee, expire_by, client_ttl, ttl \\ 0) do
    {sender, sender_priv_key} = Keys.keypair(:sign)

    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    name_update(sender, sender_priv_key, name, pointers, fee, nonce, expire_by, client_ttl, ttl)
  end

  @doc """
  Builds a NameUpdateTx from the given sender keys
  """
  @spec name_update(
          Keys.pubkey(),
          Keys.sign_priv_key(),
          String.t(),
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def name_update(
        sender,
        sender_priv_key,
        name,
        pointers,
        fee,
        nonce,
        expire_by,
        client_ttl,
        ttl \\ 0
      ) do
    case NameUtil.normalized_namehash(name) do
      {:ok, namehash} ->
        payload = %{
          hash: namehash,
          expire_by: Chain.top_height() + 1 + expire_by,
          client_ttl: client_ttl,
          pointers: pointers
        }

        build_tx(payload, NameUpdateTx, sender, sender_priv_key, fee, nonce, ttl)

      err ->
        err
    end
  end

  @doc """
  Builds a NameTransferTx where the miners public key is used as a sender
  """
  @spec name_transfer(String.t(), binary(), non_neg_integer(), non_neg_integer()) ::
          {:ok, SignedTx.t()} | {:error, String.t()}
  def name_transfer(name, target, fee, ttl \\ 0) do
    {sender, sender_priv_key} = Keys.keypair(:sign)

    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    name_transfer(sender, sender_priv_key, name, target, fee, nonce, ttl)
  end

  @doc """
  Builds a NameTransferTx from the given sender keys
  """
  @spec name_transfer(
          Keys.pubkey(),
          Keys.sign_priv_key(),
          String.t(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def name_transfer(sender, sender_priv_key, name, target, fee, nonce, ttl \\ 0) do
    case NameUtil.normalized_namehash(name) do
      {:ok, namehash} ->
        payload = %{hash: namehash, target: target}
        build_tx(payload, NameTransferTx, sender, sender_priv_key, fee, nonce, ttl)

      err ->
        err
    end
  end

  @doc """
  Builds a NameTransferTx where the miners public key is used as a sender
  """
  @spec name_revoke(String.t(), non_neg_integer(), non_neg_integer()) ::
          {:ok, SignedTx.t()} | {:error, String.t()}
  def name_revoke(name, fee, ttl \\ 0) do
    {sender, sender_priv_key} = Keys.keypair(:sign)

    nonce = Account.nonce(Chain.chain_state().accounts, sender) + 1
    name_revoke(sender, sender_priv_key, name, fee, nonce, ttl)
  end

  @doc """
  Builds a NameRevokeTx from the given sender keys
  """
  @spec name_revoke(
          Keys.pubkey(),
          Keys.sign_priv_key(),
          String.t(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def name_revoke(sender, sender_priv_key, name, fee, nonce, ttl \\ 0) do
    case NameUtil.normalized_namehash(name) do
      {:ok, namehash} ->
        payload = %{hash: namehash}
        build_tx(payload, NameRevokeTx, sender, sender_priv_key, fee, nonce, ttl)

      err ->
        err
    end
  end

  @spec build_tx(
          map(),
          DataTx.tx_types(),
          binary(),
          binary(),
          non_neg_integer(),
          non_neg_integer(),
          non_neg_integer()
        ) :: {:ok, SignedTx.t()} | {:error, String.t()}
  def build_tx(payload, tx_type, sender, sender_prv, fee, nonce, ttl \\ 0) do
    tx = DataTx.init(tx_type, payload, sender, fee, nonce, ttl)
    SignedTx.sign_tx(tx, sender, sender_prv)
  end

  @doc """
  Adds balance to the given Account state
  """
  @spec apply_transfer!(Account.t(), non_neg_integer(), integer()) :: Account.t()
  def apply_transfer!(account_state, _block_height, amount) do
    new_balance = account_state.balance + amount

    if new_balance < 0 do
      throw({:error, "#{__MODULE__}: Negative balance"})
    end

    %Account{account_state | balance: new_balance}
  end

  @spec apply_nonce!(Account.t(), integer()) :: Account.t()
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

  @spec encode_to_list(Account.t()) :: list() | {:error, String.t()}
  def encode_to_list(%Account{} = account) do
    [
      :binary.encode_unsigned(@version),
      :binary.encode_unsigned(account.nonce),
      :binary.encode_unsigned(account.balance)
    ]
  end

  @spec decode_from_list(integer(), list()) :: {:ok, Account.t()} | {:error, String.t()}
  def decode_from_list(@version, [nonce, balance]) do
    {:ok,
     %Account{
       id: %Identifier{type: :account},
       balance: :binary.decode_unsigned(balance),
       nonce: :binary.decode_unsigned(nonce)
     }}
  end

  def decode_from_list(@version, data) do
    {:error, "#{__MODULE__}: decode_from_list: Invalid serialization: #{inspect(data)}"}
  end

  def decode_from_list(version, _) do
    {:error, "#{__MODULE__}: decode_from_list: Unknown version #{version}"}
  end
end
