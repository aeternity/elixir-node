defmodule Aecore.Structures.AccountHandler do
  @moduledoc """
  Module that works with Account.t() merkle tree.
  """

  alias Aecore.Structures.Account
  alias Aecore.Structures.AccountStateTree

  @doc """
  Searching a value in the tree with a given key.
  """
  @spec get_account_state(AccountStateTree.tree(), Wallet.pubkey()) :: Account.t()
  def get_account_state(tree, key) do
    case AccountStateTree.get(tree, key) do
      :none ->
        tree
        |> AccountStateTree.put(key, Account.empty())
        |> get_account_state(key)

      {:ok, account_state} ->
        account_state
    end
  end

  @doc """
  Return the balance for a given key.
  """
  @spec balance(AccountStateTree.tree(), Wallet.pubkey()) :: integer()
  def balance(tree, key) do
    get_account_state(tree, key).balance
  end

  @doc """
  Return the nonce for a given key.
  """
  @spec nonce(AccountStateTree.tree(), Wallet.pubkey()) :: integer()
  def nonce(tree, key) do
    get_account_state(tree, key).nonce
  end
end
