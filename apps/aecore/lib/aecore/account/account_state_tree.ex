defmodule Aecore.Account.AccountStateTree do
  @moduledoc """
  Top level account state tree.
  """
  alias Aecore.Account.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Chain.Chainstate
  @type encoded_account_state :: binary()

  # abstract datatype representing a merkle tree
  @type tree :: :gb_merkle_trees.tree()
  @type accounts_state :: tree()
  @type hash :: binary()

  @spec init_empty() :: tree()
  def init_empty do
    :gb_merkle_trees.empty()
  end

  @spec put(tree(), Wallet.pubkey(), Account.t()) :: tree()
  def put(tree, key, value) do
    acc = Map.put(value, :pubkey, key)
    serialized_account_state = Account.rlp_encode(acc)
    :gb_merkle_trees.enter(key, serialized_account_state, tree)
  end

  @spec get(tree(), Wallet.pubkey()) :: binary() | :none | Account.t()
  def get(tree, key) do
    case :gb_merkle_trees.lookup(key, tree) do
      :none ->
        Account.empty()

      account_state ->
        {:ok, acc} = Chainstate.rlp_decode(account_state)
        acc
    end
  end

  @spec update(tree(), Wallet.pubkey(), (Account.t() -> Account.t())) :: tree()
  def update(tree, key, fun) do
    put(tree, key, fun.(get(tree, key)))
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

  @spec reduce(tree(), integer(), fun()) :: integer()
  def reduce(tree, acc, fun) do
    :gb_merkle_trees.foldr(fun, acc, tree)
  end

  @spec size(tree()) :: non_neg_integer()
  def size(tree) do
    :gb_merkle_trees.size(tree)
  end
end
