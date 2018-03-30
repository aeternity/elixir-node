defmodule AeutilPatriciaMerkleTreeTest do
  use ExUnit.Case

  alias Aeutil.PatriciaMerkleTree

  @tag :patricia_merkle_tree
  @tag timeout: 30_000
  test "Proof Success Tests" do
    {trie, list} = create_random_trie_test()

    Enum.each(list, fn {key, value} ->
      {:ok, ^value, proof} = PatriciaMerkleTree.lookup_with_proof(key, trie)
      assert true = PatriciaMerkleTree.verify_proof(key, value, trie, proof)
    end)
  end

  @tag :patricia_merkle_tree
  @tag timeout: 30_000
  test "Lookup Tests" do
    trie = PatriciaMerkleTree.new(:trie)
    trie = PatriciaMerkleTree.enter("key", "val", trie)

    assert {:ok, "val"} = PatriciaMerkleTree.lookup("key", trie)
    assert :none = PatriciaMerkleTree.lookup("key2", trie)

    ## Creating new trie from previous root_hash.

    prev_root_hash = trie.root_hash
    trie2 = PatriciaMerkleTree.new(:proof, prev_root_hash)

    assert {:ok, "val"} = PatriciaMerkleTree.lookup("key", trie2)
  end

  @tag :patricia_merkle_tree
  @tag timeout: 30_000
  test "Enter Tests" do
    trie = PatriciaMerkleTree.new(:trie)
    {trie, list} = create_random_trie_test()

    Enum.each(list, fn {key, value} ->
      assert %{db: _, root_hash: _} = PatriciaMerkleTree.enter(key, value, trie)
    end)
  end

  def init_proof_trie(), do: PatriciaMerkleTree.new(:proof)

  def create_random_trie_test() do
    db = PatriciaMerkleTree.new(:trie)
    list = get_random_tree_list()

    trie =
      Enum.reduce(list, db, fn {key, val}, acc_trie ->
        PatriciaMerkleTree.enter(key, val, acc_trie)
      end)

    {trie, list}
  end

  def get_random_tree_list(), do: for(_ <- 0..10_000, do: {random_key(), "0000"})

  def random_key() do
    <<:rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4>>
  end
end
