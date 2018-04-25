defmodule Aecore.Oracle.OracleStateTree do
  @moduledoc """
  Top level oracle state tree.
  """
  alias Aecore.Oracle.Oracle
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Serialization
  alias Aeutil.PatriciaMerkleTree

  @type encoded_oracle_state :: binary()

  # abstract datatype representing a merkle tree
  @type tree :: tuple()
  @type oracle_state :: Trie.t()
  @type hash :: binary()

  @spec init_empty() :: tree()
  def init_empty do
    %{registered_oracles: %{}, interaction_objects: %{}}
  end

  def init_empty1 do
    :oracles
    |> PatriciaMerkleTree.new()
    |> init_static_oracle_key()
  end

  defp init_static_oracle_key(trie) do
    Enum.reduce(Oracle.oracles_fields(), trie, fn oracle_key, acc_trie ->
      serialized_key = serialize_key(oracle_key)
      serialized_value = serialize_value(%{})
      PatriciaMerkleTree.enter(acc_trie, serialized_key, serialized_value)
    end)
  end

  def get_registered_oracles(trie) do
    {:ok, value} =
      trie
      |> PatriciaMerkleTree.lookup(serialize_key(:registered_oracles))

    deserialize_value(value)
  end

  def get_registered_oracle_by_key(trie, key) do
    trie
    |> get_registered_oracles()
    |> Map.get(key)
  end

  def get_interaction_objects(trie) do
    {:ok, value} =
      trie
      |> PatriciaMerkleTree.lookup(serialize_key(:interaction_objects))

    deserialize_value(value)
  end

  def get_interaction_object_by_key(trie, key) do
    trie
    |> get_interaction_objects()
    |> Map.get(key)
  end

  def put_registered_oracles(trie, new_oracle) do
    updated_oracles =
      trie
      |> get_registered_oracles()
      |> Map.merge(new_oracle)

    oracles_serialized = serialize_value(updated_oracles)
    key_serialized = serialize_key(:registered_oracles)
    PatriciaMerkleTree.enter(trie, key_serialized, oracles_serialized)
  end

  def put_interaction_objects(trie, new_object) do
    updated_iteraction_objects =
      trie
      |> get_interaction_objects()
      |> Map.merge(new_object)

    objects_serialized = serialize_value(updated_iteraction_objects)
    key_serialized = serialize_key(:interaction_objects)
    PatriciaMerkleTree.enter(trie, key_serialized, objects_serialized)
  end

  def has_key?(trie, key) do
    PatriciaMerkleTree.lookup(trie, key) != :none
  end

  defp serialize_key(key) do
    to_string(key)
  end

  defp deserialize_key(key) do
    String.to_atom(key)
  end

  defp serialize_value(value) do
    # Must be done using RPL encoding when is done GH-335
    :erlang.term_to_binary(value)
  end

  defp deserialize_value(value) do
    # Must be done using RPL dencoding when is done GH-335
    :erlang.binary_to_term(value)
  end

  # @spec delete(tree(), Wallet.pubkey()) :: tree()
  # def delete(tree, key) do
  #   :gb_merkle_trees.delete(key, tree)
  # end

  # @spec root_hash(tree()) :: hash()
  # def root_hash(tree) do
  #   :gb_merkle_trees.root_hash(tree)
  # end
end
