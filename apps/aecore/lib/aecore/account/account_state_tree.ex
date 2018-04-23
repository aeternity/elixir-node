defmodule Aecore.Account.AccountStateTree do
  @moduledoc """
  Top level account state tree.
  """
  alias Aecore.Account.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Serialization
  alias Aeutil.PatriciaMerkleTree

  require Logger

  @type accounts_state :: Trie.t()
  @type hash :: binary()

  @spec init_empty() :: Trie.t()
  def init_empty do
    PatriciaMerkleTree.new(:account)
  end

  @spec put(Trie.t(), Wallet.pubkey(), Account.t()) :: Trie.t()
  def put(trie, key, value) do
    serialized = Serialization.serialize_term(value)
    PatriciaMerkleTree.enter(trie, key, serialized)
  end

  @spec get(Trie.t(), Wallet.pubkey()) :: Account.t()
  def get(trie, key) do
    trie
    |> PatriciaMerkleTree.lookup(key)
    |> Serialization.deserialize_term()
  end

  def has_key?(trie, key) do
    PatriciaMerkleTree.lookup(trie, key) != :none
  end

  # @spec delete(tree(), Wallet.pubkey()) :: tree()
  # def delete(tree, key) do
  #   :gb_merkle_trees.delete(key, tree)
  # end

  # @spec balance(tree()) :: tree()
  # def balance(tree) do
  #   :gb_merkle_trees.balance(tree)
  # end

  @spec root_hash(Trie.t()) :: hash()
  def root_hash(trie) do
    PatriciaMerkleTree.root_hash(trie)
  end

  @spec reduce(Trie.t(), any(), fun()) :: any()
  def reduce(tree, acc, fun) do
    Logger.error(fn ->
      "#{__MODULE__}: Calculate total tokens. Error function not implemented (reduce)"
    end)

    0
  end

  @spec size(Trie.t()) :: non_neg_integer()
  def size(tree) do
    1
  end
end
