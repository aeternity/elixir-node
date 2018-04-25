defmodule Aecore.Account.AccountStateTree do
  @moduledoc """
  Top level account state tree.
  """
  alias Aecore.Account.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Serialization
  alias Aeutil.PatriciaMerkleTree

  @type accounts_state :: Trie.t()
  @type hash :: binary()

  @spec init_empty() :: Trie.t()
  def init_empty do
    PatriciaMerkleTree.new(:accounts)
  end

  @spec put(accounts_state(), Wallet.pubkey(), Account.t()) :: accounts_state()
  def put(trie, key, value) do
    serialized = Serialization.serialize_term(value)
    PatriciaMerkleTree.enter(trie, key, serialized)
  end

  @spec get(accounts_state(), Wallet.pubkey()) :: Account.t()
  def get(trie, key) do
    trie
    |> PatriciaMerkleTree.lookup(key)
    |> Serialization.deserialize_term()
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
