defmodule Aecore.Structures.AccountStateTree do
  @moduledoc """
  Top level account state tree.
  """
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Serialization
  @type encoded_account_state :: binary()

  # abstract datatype representing a merkle tree
  @type tree :: tuple()
  @type accounts_state :: tree()
  @type hash :: binary()

  @spec init_empty() :: tree()
  def init_empty do
    :gb_merkle_trees.empty()
  end

  @spec put(tree(), Wallet.pubkey(), Account.t()) :: tree()
  def put(tree, key, value) do
    serialized_account_state = Serialization.account_state(value, :serialize)
    :gb_merkle_trees.enter(key, serialized_account_state, tree)
  end

  @spec get(tree(), Wallet.pubkey()) :: Account.t()
  def get(tree, key) do
    account_state = :gb_merkle_trees.lookup(key, tree)
    Serialization.account_state(account_state, :deserialize)
  end

  def has_key?(tree, key) do
    :gb_merkle_trees.lookup(key, tree) != :none
  end

  @spec delete(tree(), Wallet.pubkey()) :: tree()
  def delete(tree, key) do
    :gb_merkle_trees.delete(key, tree)
  end

  @spec balance(tree()) :: tree()
  def balance(tree) do
    :gb_merkle_trees.balance(tree)
  end

  @spec root_hash(tree()) :: hash()
  def root_hash(tree) do
    :gb_merkle_trees.root_hash(tree)
  end

  @spec reduce(tree(), any(), fun()) :: any()
  def reduce(tree, acc, fun) do
    :gb_merkle_trees.foldr(fun, acc, tree)
  end

  @spec size(tree()) :: non_neg_integer()
  def size(tree) do
    :gb_merkle_trees.size(tree)
  end
end
