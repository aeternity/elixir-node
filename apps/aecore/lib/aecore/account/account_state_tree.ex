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
    serialized = serialize(value)
    PatriciaMerkleTree.enter(trie, key, serialized)
  end

  @spec get(accounts_state(), Wallet.pubkey()) :: Account.t()
  def get(trie, key) do
    trie
    |> PatriciaMerkleTree.lookup(key)
    |> deserialize()
    |> retutn_emty_if_account_doesnot_exist()
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

  def retutn_emty_if_account_doesnot_exist(:none), do: Account.empty()
  def retutn_emty_if_account_doesnot_exist(%Account{} = account), do: account

  defp serialize(term), do: term |> :erlang.term_to_binary()
  defp deserialize(:none), do: :none
  defp deserialize({:ok, binary}), do: deserialize(binary)
  defp deserialize(binary), do: binary |> :erlang.binary_to_term()
end
