defmodule Aecore.Account.AccountStateTree do
  @moduledoc """
  Top level account state tree.
  """
  alias Aecore.Account.Account
  alias Aecore.Keys.Wallet
  alias Aeutil.Serialization
  alias Aeutil.PatriciaMerkleTree
  alias MerklePatriciaTree.Trie
  alias Aecore.Chain.Identifier

  @type accounts_state :: Trie.t()
  @type hash :: binary()

  @spec init_empty() :: accounts_state()
  def init_empty do
    PatriciaMerkleTree.new(:accounts)
  end

  @spec put(accounts_state(), Wallet.pubkey(), Account.t()) :: accounts_state()
  def put(trie, key, value) do
    serialized_account_state = Serialization.rlp_encode(value, :account_state)
    PatriciaMerkleTree.enter(trie, key, serialized_account_state)
  end

  @spec get(accounts_state(), Wallet.pubkey()) :: Account.t()
  def get(tree, key) do
    case PatriciaMerkleTree.lookup(tree, key) do
      :none ->
        Account.empty()

      {:ok, account_state} ->
        {:ok, acc} = Serialization.rlp_decode(account_state)

        {:ok, id} = Identifier.create_identity(key, :account)
        %Account{acc | id: id}
    end
  end

  @spec update(accounts_state(), Wallet.pubkey(), (Account.t() -> Account.t())) ::
          accounts_state()
  def update(tree, key, fun) do
    put(tree, key, fun.(get(tree, key)))
  end

  @spec has_key?(accounts_state(), Wallet.pubkey()) :: boolean()
  def has_key?(tree, key) do
    PatriciaMerkleTree.lookup(tree, key) != :none
  end

  @spec root_hash(accounts_state()) :: hash()
  def root_hash(tree) do
    PatriciaMerkleTree.root_hash(tree)
  end
end
