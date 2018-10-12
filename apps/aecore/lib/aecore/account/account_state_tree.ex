defmodule Aecore.Account.AccountStateTree do
  @moduledoc """
  Top level account state tree.
  """
  alias Aecore.Account.Account
  alias Aecore.Chain.Identifier
  alias Aecore.Keys
  alias Aeutil.PatriciaMerkleTree
  alias MerklePatriciaTree.Trie

  @typedoc "Accounts tree"
  @type accounts_state :: Trie.t()

  @typedoc "Hash of the tree"
  @type hash :: binary()

  @type error :: {:error, String.t()}

  @spec init_empty() :: accounts_state()
  def init_empty do
    PatriciaMerkleTree.new(:accounts)
  end

  @spec put(accounts_state(), Keys.pubkey(), Account.t()) :: accounts_state()
  def put(tree, key, value) do
    serialized_account_state = Account.rlp_encode(value)
    PatriciaMerkleTree.enter(tree, key, serialized_account_state)
  end

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

  @spec has_key?(accounts_state(), Keys.pubkey()) :: boolean()
  def has_key?(tree, key) do
    PatriciaMerkleTree.lookup(tree, key) != :none
  end

  @spec root_hash(accounts_state()) :: hash()
  def root_hash(tree) do
    PatriciaMerkleTree.root_hash(tree)
  end
end
