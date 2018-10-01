defmodule AeutilPatriciaMerkleTreeTest do
  use ExUnit.Case

  alias Aeutil.PatriciaMerkleTree

  setup do
    on_exit(fn ->
      :ok
    end)

    %{db_ref_name: :test_trie, trie: PatriciaMerkleTree.new(:test_trie)}
  end

  @tag :patricia_merkle_tree_proof
  @tag timeout: 30_000
  test "Proof Success", %{trie: empty_trie} do
    trie_list = gen_random_tree_list()
    trie = create_trie(trie_list, empty_trie)

    Enum.each(trie_list, fn {key, value} ->
      {:ok, ^value, proof} = PatriciaMerkleTree.lookup_with_proof(trie, key)
      assert true = PatriciaMerkleTree.verify_proof?(key, value, trie.root_hash, proof)
    end)

    assert :none = PatriciaMerkleTree.lookup_with_proof(trie, "not_existing_key")
  end

  @tag :patricia_merkle_tree
  @tag timeout: 30_000
  test "Lookup", %{db_ref_name: db_ref_name, trie: empty_trie} do
    # Creating trie with only one leaf node.
    trie = PatriciaMerkleTree.enter(empty_trie, "key", "val")

    # Retrieving the value of the leaf
    assert {:ok, "val"} = PatriciaMerkleTree.lookup(trie, "key")

    # There is no such path `key2` so we should get `:none`
    assert :none = PatriciaMerkleTree.lookup(trie, "key2")

    # Creating new trie from previous root_hash
    # and the expected result should be the value
    # of the existing leaf in the first trie.
    trie2 = PatriciaMerkleTree.new(db_ref_name, trie.root_hash)

    assert {:ok, "val"} = PatriciaMerkleTree.lookup(trie2, "key")
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
    trie = PatriciaMerkleTree.insert(empty_trie, "key", "a")
    assert {:ok, "a"} = PatriciaMerkleTree.lookup(trie, "key")
    assert {:error, :already_present} = PatriciaMerkleTree.insert(trie, "key", "a")
  end

  @tag :patricia_merkle_tree
  @tag timeout: 30_000
  test "Delete a node from trie", %{trie: empty_trie} do
    trie = PatriciaMerkleTree.insert(empty_trie, "key", "a")
    assert {:ok, "a"} = PatriciaMerkleTree.lookup(trie, "key")
    new_trie = PatriciaMerkleTree.delete(trie, "key")
    assert :none = PatriciaMerkleTree.lookup(new_trie, "key")
    assert empty_trie.root_hash == new_trie.root_hash
  end

  @tag :patricia_merkle_tree
  test "Get all keys and their size" do
    t =
      :test_trie
      |> PatriciaMerkleTree.new()
      |> PatriciaMerkleTree.enter("111", "v1")
      |> PatriciaMerkleTree.enter("112", "v2")

    assert ["111", "112"] = PatriciaMerkleTree.all_keys(t)
    assert 2 = PatriciaMerkleTree.trie_size(t)
  end

  @doc """
  Creates trie from trie list by entering each element
  """
  def create_trie(trie_list, empty_trie) do
    Enum.reduce(trie_list, empty_trie, fn {key, val}, acc_trie ->
      PatriciaMerkleTree.enter(acc_trie, key, val)
    end)
  end

  def gen_random_tree_list, do: for(_ <- 0..500, do: {random_key(), "0000"})

  def random_key do
    <<:rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4, :rand.uniform(15)::4,
      :rand.uniform(15)::4, :rand.uniform(15)::4>>
  end
end
