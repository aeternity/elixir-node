defmodule Aecore.Structures.AccountHandler do
  alias Aecore.Structures.Account
  alias Aecore.Structures.AccountStateTree

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

  @spec balance(AccountStateTree.tree(), Wallet.pubkey()) :: integer()
  def balance(tree, key) do
    get_account_state(tree, key).balance
  end

  @spec nonce(AccountStateTree.tree(), Wallet.pubkey()) :: integer()
  def nonce(tree, key) do
    get_account_state(tree, key).nonce
  end
end
