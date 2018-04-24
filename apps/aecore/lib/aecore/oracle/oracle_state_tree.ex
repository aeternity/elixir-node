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

  def put_registered_oracles(tree, oracle) do
    value_serialized = Serialization.serialize_test(oracle)

    Serialization.serialize_test(:registered_oracles)
    |> :gb_merkle_trees.enter(value_serialized, tree)
  end

  def put_interaction_objects(tree, object) do
    value_serialized = Serialization.serialize_test(object)

    Serialization.serialize_test(:interaction_objects)
    |> :gb_merkle_trees.enter(value_serialized, tree)
  end

  def get_registered_oracles(tree) do
    value =
      Serialization.serialize_test(:registered_oracles)
      |> :gb_merkle_trees.lookup(tree)

    case value do
      :none -> %{}
      _ -> Serialization.deserialize_test(value)
    end
  end

  def get_interaction_objects(tree) do
    value =
      Serialization.serialize_test(:interaction_objects)
      |> :gb_merkle_trees.lookup(tree)

    case value do
      :none -> %{}
      _ -> Serialization.deserialize_test(value)
    end
  end

  # def has_key?(tree, key) do
  #   :gb_merkle_trees.lookup(key, tree) != :none
  # end

  # @spec delete(tree(), Wallet.pubkey()) :: tree()
  # def delete(tree, key) do
  #   :gb_merkle_trees.delete(key, tree)
  # end

  @spec balance(tree()) :: tree()
  def balance(tree) do
    :gb_merkle_trees.balance(tree)
  end

  @spec root_hash(tree()) :: hash()
  def root_hash(tree) do
    :gb_merkle_trees.root_hash(tree)
  end

  @spec reduce(tree(), any(), fun()) :: any()
  def reduce(tree, acc, fun) do
    :gb_merkle_trees.foldr(fun, acc, tree)
  end

  @spec size(tree()) :: non_neg_integer()
  def size(tree) do
    :gb_merkle_trees.size(tree)
  end
end
