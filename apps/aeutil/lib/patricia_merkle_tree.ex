defmodule Aeutil.PatriciaMerkleTree do
  @moduledoc """

  This module provides apis for creating, updating, deleting
  patricia merkle tries, The actual handler is https://github.com/exthereum/merkle_patricia_tree

  """

  alias Aeutil.Serialization
  alias MerklePatriciaTree.Trie
  alias MerklePatriciaTree.Proof
  alias MerklePatriciaTree.DB.ExternalDB
  alias MerklePatriciaTree.Trie.Inspector

  alias Aecore.Persistence.Worker, as: Persistence

  @typedoc """
  Depending on the name, different data base ref will
  be used for the trie creaton.
  """
  @type trie_name ::
          :accounts
          | :txs
          | :proof
          | :oracles
          | :oracles_cache
          | :naming
          | :channels
          | :contracts
          | :calls

  @spec root_hash(Trie.t()) :: binary
  def root_hash(%{root_hash: root_hash}), do: root_hash

  @doc """
  Creating new trie.
  """
  @spec new(trie_name()) :: Trie.t()
  def new(trie_name), do: Trie.new(ExternalDB.init(get_db_handlers(trie_name)))

  @doc """
  Create new trie with specific hash root
  """
  @spec new(trie_name(), binary) :: Trie.t()
  def new(trie_name, root_hash) do
    Trie.new(ExternalDB.init(get_db_handlers(trie_name)), root_hash)
  end

  @spec new(trie_name()) :: Trie.t()
  defp get_db_handlers(trie_name) do
    %{put: Persistence.db_handler_put(trie_name), get: Persistence.db_handler_get(trie_name)}
  end

  @doc """
  Retrieve value from trie.
  """
  @spec lookup(Trie.t(), Trie.key()) :: {:ok, Trie.value()} | :none
  def lookup(trie, key) do
    case Trie.get(trie, key) do
      nil -> :none
      val -> {:ok, val}
    end
  end

  @doc """
  Retrieve value from trie and construct proof.
  """
  @spec lookup_with_proof(Trie.trie(), Trie.key()) :: :none | {:ok, Trie.value(), Trie.t()}
  def lookup_with_proof(trie, key) do
    case Proof.construct_proof({trie, key, new(:proof)}) do
      {nil, _proof} -> :none
      {val, proof} -> {:ok, val, proof}
    end
  end

  @doc """
  Check if the value already exists for this key before add it.
  If so return error message.
  """
  @spec insert(Trie.t(), Trie.key(), Trie.value()) :: Trie.t() | {:error, term}
  def insert(trie, key, value) do
    case lookup(trie, key) do
      {:ok, _value} ->
        {:error, :already_present}

      :none ->
        Trie.update(trie, key, value)
    end
  end

  @spec enter(Trie.t(), Trie.key(), Trie.value()) :: Trie.t()
  def enter(trie, key, value), do: Trie.update(trie, key, value)

  @doc """
  Verify if value is present in the proof trie for the provided key.
  The key represents the path in the proof trie.
  """
  @spec verify_proof?(Trie.key(), Trie.value(), binary(), Trie.t()) :: boolean
  def verify_proof?(key, value, root_hash, proof) do
    case Proof.verify_proof(key, value, root_hash, proof) do
      :ok ->
        true

      {:error, _} ->
        false
    end
  end

  @doc """
  Lookups the value associated with the given key in the proof trie.
  """
  @spec lookup_proof(Trie.key(), binary(), Trie.t()) :: {:ok, Trie.value()} | :error
  def lookup_proof(key, root_hash, proof) do
    case Proof.lookup_proof(key, root_hash, proof) do
      nil ->
        :error

      {:error, _} ->
        :error

      val ->
        {:ok, val}
    end
  end

  @doc """
  Deleting a value for given key and reorganizing the trie
  """
  @spec delete(Trie.t(), Trie.key()) :: Trie.t()
  def delete(trie, key), do: Trie.delete(trie, key)

  @doc """
  Providing debug print of a given trie in the shell
  """
  @spec print_debug(Trie.t()) :: Trie.t() | list() | {:error, term()}
  def print_debug(trie), do: print_trie(trie, output: :as_pair, deserialize: true)

  @doc """
  Providing pretty print of a given trie in the shell.
  Depending on the atom it can print structure or key value pairs. The default output is :as_struct

  # Examples

  If we want to print as pair and no serialization is needed
      iex> Aeutil.PatriciaMerkleTree.new(:test_trie) |> Aeutil.PatriciaMerkleTree.enter("111", "val1") |> Aeutil.PatriciaMerkleTree.enter("112", "val2") |> Aeutil.PatriciaMerkleTree.print_trie([output: :as_pair, deserialize: false])
      [{"111", "v1"}, {"112", "v2"}]

  If we want to print as pair and serialization is needed
      iex> Chain.get_chain_state_by_height(1).accounts |> PatriciaMerkleTree.print_trie([output: :as_pair, deserialize: true])
      [
        {<<3, 198, 106, 104, 110, 21, 75, 215, 141, 232, 196, 72, 106, 43, 188, 85,
         47, 30, 208, 235, 189, 51, 92, 132, 247, 27, 130, 183, 118, 136, 119, 33,
         190>>,
        %Aecore.Account.Account{
          balance: 100,
          nonce: 0,
          pubkey: <<3, 198, 106, 104, 110, 21, 75, 215, 141, 232, 196, 72, 106, 43,
                   188, 85, 47, 30, 208, 235, 189, 51, 92, 132, 247, 27, 130, 183, 118, 136,
                   119, 33, 190>>
        }}
     ]

  If we want to print the whole struct. Returns the trie as well.
      iex> Aeutil.PatriciaMerkleTree.new(:test_trie) |> Aeutil.PatriciaMerkleTree.enter("111", "val1") |> Aeutil.PatriciaMerkleTree.enter("112", "val2") |> Aeutil.PatriciaMerkleTree.print_trie()
      ~~~~~~Trie~~~
      Node: ext (prefix: [3, 1, 3, 1, 3])
        Node: branch (value: "")
          [0] Node: <empty>
          [1] Node: leaf ([]="val1")
          [2] Node: leaf ([]="val2")
          [3] Node: <empty>
          [4] Node: <empty>
          [5] Node: <empty>
          [6] Node: <empty>
          [7] Node: <empty>
          [8] Node: <empty>
          [9] Node: <empty>
          [10] Node: <empty>
          [11] Node: <empty>
          [12] Node: <empty>
          [13] Node: <empty>
          [14] Node: <empty>
          [15] Node: <empty>
      ~~~/Trie/~~~

  If the given type is incorrect
      iex> Aeutil.PatriciaMerkleTree.new(:test_trie) |> Aeutil.PatriciaMerkleTree.enter("111", "val1") |> Aeutil.PatriciaMerkleTree.enter("112", "val2") |> Aeutil.PatriciaMerkleTree.print_trie(:wrong_type)
      {:error, "Unknown print type"}
  """
  @spec print_trie(Trie.t(), keyword()) :: Trie.t() | list() | {:error, term()}
  def print_trie(trie, opts \\ [output: :as_struct, deserialize: false]) do
    print_trie(trie, opts[:output], opts[:deserialize])
  end

  def print_trie(trie, :as_struct, _), do: Inspector.inspect_trie(trie)

  def print_trie(trie, :as_pair, false), do: Inspector.all_values(trie)

  def print_trie(trie, :as_pair, _) do
    list = Inspector.all_values(trie)

    Enum.reduce(list, [], fn {key, val}, acc ->
      [{key, elem(Serialization.rlp_decode_anything(val), 1)} | acc]
    end)
  end

  def print_trie(_, _, _), do: {:error, "Unknown print type"}

  @doc """
  Retrieving all keys of a given trie
  """
  @spec all_keys(Trie.t()) :: list(Trie.key())
  def all_keys(trie), do: Inspector.all_keys(trie)

  @doc """
  Count all keys of a given trie
  """
  @spec trie_size(Trie.t()) :: integer()
  def trie_size(trie), do: length(all_keys(trie))
end
