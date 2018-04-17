defmodule Aeutil.PatriciaMerkleTree do
  @moduledoc """

  This module provides apis for creating, updating, deleting
  patricia merkle tries, The actual handler is https://github.com/exthereum/merkle_patricia_tree

  """

  alias MerklePatriciaTree.Trie
  alias MerklePatriciaTree.Proof
  alias MerklePatriciaTree.DB.ExternalDB

  alias Aecore.Persistence.Worker, as: Persistence

  @typedoc """
  Depending on the name, different data base ref will
  be used for the trie creaton.
  """
  @type trie_name :: :account | :txs | :proof

  @spec root_hash(Trie.t()) :: binary
  def root_hash(%{root_hash: root_hash}), do: root_hash

  @doc """
  Creating new trie.
  """
  @spec new(trie_name) :: Trie.t()
  def new(trie_name), do: Trie.new(ExternalDB.init(get_db_handlers(trie_name)))

  @doc """
  Create new trie with specific hash root
  """
  @spec new(trie_name, binary) :: Trie.t()
  def new(trie_name, root_hash) do
    Trie.new(ExternalDB.init(get_db_handlers(trie_name)), root_hash)
  end

  @spec new(trie_name) :: Trie.t()
  defp get_db_handlers(trie_name) do
    %{put: Persistence.db_handler_put(trie_name), get: Persistence.db_handler_get(trie_name)}
  end

  @doc """
  Retrieve value from trie.
  """
  @spec lookup(Trie.key(), Trie.t()) :: {:ok, Trie.value()} | :none
  def lookup(key, trie) do
    case Trie.get(trie, key) do
      nil -> :none
      val -> {:ok, val}
    end
  end

  @doc """
  Retrieve value from trie and construct proof.
  """
  @spec lookup_with_proof(Trie.key(), Trie.t()) :: :none | {:ok, Trie.value(), Trie.t()}
  def lookup_with_proof(key, trie) do
    case Proof.construct_proof({trie, key, new(:proof)}) do
      {nil, _proof} -> :none
      {val, proof} -> {:ok, val, proof}
    end
  end

  @doc """
  Check if the value already exists for this key before add it.
  If so return error message.
  """
  @spec insert(Trie.key(), Trie.value(), Trie.t()) :: Trie.t() | {:error, term}
  def insert(key, value, trie) do
    case lookup(key, trie) do
      {:ok, ^value} ->
        {:error, :already_present}

      :none ->
        Trie.update(trie, key, value)
    end
  end

  @spec enter(Trie.key(), Trie.value(), Trie.t()) :: Trie.t()
  def enter(key, value, trie), do: Trie.update(trie, key, value)

  @doc """
  Verify if value is present in the proof trie for the provided key.
  The key represents the path in the proof trie.
  """
  @spec verify_proof(Trie.key(), Trie.value(), Trie.t(), Trie.t()) :: boolean
  def verify_proof(key, value, trie, proof) do
    Proof.verify_proof(key, value, trie.root_hash, proof.db)
  end

  @doc """
  Deleting a value for given key and reorganizing the trie
  """
  @spec delete(Trie.key(), Trie.t()) :: Trie.t()
  def delete(key, trie), do: Trie.delete(trie, key)
end
