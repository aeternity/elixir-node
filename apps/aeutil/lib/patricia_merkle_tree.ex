defmodule Aeutil.PatriciaMerkleTree do
  @moduledoc """

  TODO

  """

  alias MerklePatriciaTree.Trie
  alias MerklePatriciaTree.Proof
  alias MerklePatriciaTree.DB.ExternalDB

  alias Aecore.Persistence.Worker, as: Persistence

  @spec root_hash(Trie.t()) :: binary()
  def root_hash(%{root_hash: root_hash}), do: root_hash

  @spec lookup(Trie.key(), Trie.t()) :: {:ok, Trie.value()} | :none
  def lookup(key, trie) do
    Trie.get(trie, key)
  end

  @spec lookup_with_proof(Trie.key(), Trie.t()) ::
  :none | {:ok, Trie.value(), Trie.t()}
  def lookup_with_proof(key, trie) do
    put = Persistence.db_handler_put(:proof)
    get = Persistence.db_handler_get(:proof)

    proof = Trie.new(ExternalDB.init(%{put: put, get: get}))
    {value, proof} = Proof.construct_proof({trie, key, proof})
    {:ok, value, proof}
  end

  @spec insert(Trie.key(), Trie.value(), Trie.t()) :: Trie.t() | {:error, term()}
  def insert(key, value, trie) do
    case lookup(key, trie) do
      {:ok, ^value} ->
        {:error, :already_present}

      :none ->
        Trie.update(trie, key, value)
    end
  end

  @spec enter(Trie.key(), Trie.value(), Trie.t()) :: Trie.t()
  def enter(key, value, trie) do
    Trie.update(trie, key, value)
  end

  @spec verify_proof(Trie.key(), Trie.value(), Trie.t(), Trie.t()) :: boolean()
  def verify_proof(key, value, trie, proof) do
    Proof.verify_proof(key, value, trie.root_hash, proof.db)
  end

end
