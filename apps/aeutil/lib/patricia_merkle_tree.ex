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

  @doc """
  Creating new trie
  """
  @spec new(trie_name :: atom()) :: Trie.t()
  def new(trie_name) do
    Trie.new(ExternalDB.init(get_db_handlers(trie_name)))
  end

  @doc """
  Create new trie with specific hash root
  """
  @spec new(trie_name :: atom(), binary()) :: Trie.t()
  def new(trie_name, root_hash) do
    Trie.new(ExternalDB.init(get_db_handlers(trie_name)), root_hash)
  end

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
    {value, proof} = Proof.construct_proof({trie, key, new(:proof)})
    {:ok, value, proof}
  end

  @doc """
  Check if the value already exists for this key before add it.
  If so return error message.
  """
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

  @doc """
  Verify if value is present in the proof trie for the provided key.
  The key represents the path in the proof trie.
  """
  @spec verify_proof(Trie.key(), Trie.value(), Trie.t(), Trie.t()) :: boolean()
  def verify_proof(key, value, trie, proof) do
    Proof.verify_proof(key, value, trie.root_hash, proof.db)
  end
end
