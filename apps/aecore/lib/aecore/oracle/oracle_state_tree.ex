defmodule Aecore.Oracle.OracleStateTree do
  @moduledoc """
  Top level oracle state tree.
  """
  alias Aecore.Oracle.Oracle
  alias Aeutil.PatriciaMerkleTree
  alias Aecore.Oracle.Tx.OracleRegistrationTx
  alias Aecore.Wallet.Worker, as: Wallet

  @type oracles_state :: Trie.t()
  @type hash :: binary()

  @spec init_empty() :: oracles_state()
  def init_empty do
    :oracles
    |> PatriciaMerkleTree.new()
    |> init_static_oracle_key()
  end

  @spec get_registered_oracles(oracles_state()) :: Oracle.registered_oracles()
  def get_registered_oracles(trie) do
    {:ok, value} =
      trie
      |> PatriciaMerkleTree.lookup(serialize_key(:registered_oracles))

    deserialize_value(value)
  end

  @spec get_interaction_objects(oracles_state()) :: Oracle.interaction_objects()
  def get_interaction_objects(trie) do
    {:ok, value} =
      trie
      |> PatriciaMerkleTree.lookup(serialize_key(:interaction_objects))

    deserialize_value(value)
  end

  @spec put_registered_oracles(oracles_state(), OracleRegistrationTx.t()) :: oracles_state()
  def put_registered_oracles(trie, new_oracle) do
    updated_oracles =
      trie
      |> get_registered_oracles()
      |> Map.merge(new_oracle)

    oracles_serialized = serialize_value(updated_oracles)
    key_serialized = serialize_key(:registered_oracles)
    PatriciaMerkleTree.enter(trie, key_serialized, oracles_serialized)
  end

  @spec put_interaction_objects(oracles_state(), Oracle.interaction_objects()) :: oracles_state()
  def put_interaction_objects(trie, new_object) do
    updated_iteraction_objects =
      trie
      |> get_interaction_objects()
      |> Map.merge(new_object)

    objects_serialized = serialize_value(updated_iteraction_objects)
    key_serialized = serialize_key(:interaction_objects)
    PatriciaMerkleTree.enter(trie, key_serialized, objects_serialized)
  end

  @spec delete_registered_oracle(oracles_state(), Wallet.pubkey()) :: oracles_state()
  def delete_registered_oracle(trie, key) do
    serialized_value =
      trie
      |> get_registered_oracles
      |> Map.delete(key)
      |> serialize_value()

    serialized_key = serialize_key(:registered_oracles)
    PatriciaMerkleTree.enter(trie, serialized_key, serialized_value)
  end

  @spec delete_interaction_object(oracles_state(), binary()) :: oracles_state()
  def delete_interaction_object(trie, key) do
    serialized_value =
      trie
      |> get_interaction_objects()
      |> Map.delete(key)
      |> serialize_value()

    serialized_key = serialize_key(:interaction_objects)
    PatriciaMerkleTree.enter(trie, serialized_key, serialized_value)
  end

  @spec has_key?(oracles_state(), Wallet.pubkey()) :: boolean()
  def has_key?(trie, key) do
    PatriciaMerkleTree.lookup(trie, key) != :none
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

  defp serialize_value(value) do
    # Must be done using RPL encoding when is done GH-335
    :erlang.term_to_binary(value)
  end

  defp deserialize_value(value) do
    # Must be done using RPL dencoding when is done GH-335
    :erlang.binary_to_term(value)
  end
end
