defmodule Aecore.Account.AccountStateTree do
  @moduledoc """
  Top level account state tree.
  """
  use Aecore.Util.StateTrees

  alias Aecore.Account.Account
  alias Aecore.Chain.Identifier
  alias Aecore.Keys
  alias Aeutil.PatriciaMerkleTree
  alias MerklePatriciaTree.Trie

  @typedoc "Accounts tree"
  @type accounts_state :: Trie.t()

  @typedoc "Hash of the tree"
  @type hash :: binary()

  @spec name() :: atom()
  def name(), do: :accounts

  @spec get(accounts_state(), Keys.pubkey()) :: Account.t()
  def get(tree, key) do
    case PatriciaMerkleTree.lookup(tree, key) do
      :none ->
        Account.empty()

      {:ok, account_state} ->
        {:ok, acc} = Account.rlp_decode(account_state)

        id = Identifier.create_identity(key, :account)
        %Account{acc | id: id}
    end
  end

  @spec update(accounts_state(), Keys.pubkey(), (Account.t() -> Account.t())) :: accounts_state()
  def update(tree, key, fun) do
    put(tree, key, fun.(get(tree, key)))
  end
end
