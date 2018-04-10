defmodule AeutilPatriciaMerkleTreeTest do
  use ExUnit.Case

  alias Aeutil.PatriciaMerkleTree

  setup do
    %{trie: PatriciaMerkleTree.new(:trie)}
  end

  @tag :patricia_merkle_tree_proof
  @tag timeout: 30_000
  test "Proof Success", %{trie: empty_trie} do
    trie_list = gen_random_tree_list()
    trie = create_trie(trie_list, empty_trie)

    Enum.each(trie_list, fn {key, value} ->
      {:ok, ^value, proof} = PatriciaMerkleTree.lookup_with_proof(key, trie)
      assert true = PatriciaMerkleTree.verify_proof(key, value, trie, proof)
    end)
  end

  @tag :patricia_merkle_tree
  @tag timeout: 30_000
  test "Lookup", %{trie: empty_trie} do
    ## Creating trie with only one leaf node.
    trie = PatriciaMerkleTree.enter("key", "val", empty_trie)

    ## Retrieving the value of the leaf
    assert {:ok, "val"} = PatriciaMerkleTree.lookup("key", trie)

    ## There is no such path `key2` so we should get `:none`
    assert :none = PatriciaMerkleTree.lookup("key2", trie)

    ## Creating new trie from previous root_hash
    ## and the expected result should be the value
    ## of the existing leaf in the first trie.
    trie2 = PatriciaMerkleTree.new(:proof, trie.root_hash)

    assert {:ok, "val"} = PatriciaMerkleTree.lookup("key", trie2)
  end

  @tag :patricia_merkle_tree
  @tag timeout: 30_000
  test "Enter", %{trie: empty_trie} do
    trie_list = gen_random_tree_list()
    assert %{db: _, root_hash: _} = create_trie(trie_list, empty_trie)
  end

  @tag :patricia_merkle_tree
  @tag timeout: 30_000
  test "Insert", %{trie: empty_trie} do
    trie = PatriciaMerkleTree.insert("key", "a", empty_trie)
    assert {:ok, "a"} = PatriciaMerkleTree.lookup("key", trie)
    assert {:error, :already_present} = PatriciaMerkleTree.insert("key", "a", trie)
  end

  @tag :patricia_merkle_tree
  @tag timeout: 30_000
  test "Delete a node from trie", %{trie: empty_trie} do
    trie = PatriciaMerkleTree.insert("key", "a", empty_trie)
    assert {:ok, "a"} = PatriciaMerkleTree.lookup("key", trie)
    new_trie = PatriciaMerkleTree.delete("key", trie)
    assert :none = PatriciaMerkleTree.lookup("key", new_trie)
    assert empty_trie.root_hash == new_trie.root_hash
  end

  @doc """
  Creates trie from trie list by entering each element
  """
  def create_trie(trie_list, empty_trie) do
    Enum.reduce(trie_list, empty_trie, fn {key, val}, acc_trie ->
      PatriciaMerkleTree.enter(key, val, acc_trie)
    end)
  end

  def gen_random_tree_list(), do: for(_ <- 0..10_000, do: {random_key(), "0000"})

  def random_key() do
    <<:rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4>>
  end
end
