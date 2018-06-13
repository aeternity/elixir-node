defmodule Aecore.Account.AccountStateTree do
  @moduledoc """
  Top level account state tree.
  """
  alias Aecore.Account.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Serialization
  alias Aeutil.PatriciaMerkleTree
  alias MerklePatriciaTree.Trie

  @type accounts_state :: Trie.t()

  @type hash :: binary()

  @spec init_empty() :: Trie.t()
  def init_empty do
    PatriciaMerkleTree.new(:accounts)
  end

  @spec put(accounts_state(), Wallet.pubkey(), Account.t()) :: accounts_state()
  def put(trie, key, value) do
    account_state_updated = Map.put(value, :pubkey, key)
    serialized_account_state = Serialization.rlp_encode(account_state_updated, :account_state)
    PatriciaMerkleTree.enter(trie, key, serialized_account_state)
  end

  @spec get(accounts_state(), Wallet.pubkey()) :: binary() | :none | Account.t()
  def get(trie, key) do
    case PatriciaMerkleTree.lookup(trie, key) do
      :none ->
        Account.empty()

      {:ok, account_state} ->
        {:ok, acc} = Serialization.rlp_decode(account_state)
        acc
    end
  end

  @spec update(accounts_state(), Wallet.pubkey(), (Account.t() -> Account.t())) ::
          accounts_state()
  def update(tree, key, fun) do
    put(tree, key, fun.(get(tree, key)))
  end

  @spec has_key?(accounts_state(), Wallet.pubkey()) :: boolean()
  def has_key?(trie, key) do
    PatriciaMerkleTree.lookup(trie, key) != :none
  end

  @spec root_hash(accounts_state()) :: hash()
  def root_hash(trie) do
    PatriciaMerkleTree.root_hash(trie)
  end
end
