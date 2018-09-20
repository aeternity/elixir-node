defmodule Aecore.Contract.ContractStateTree do
  @moduledoc """
  Top level contract state tree.
  """
  alias Aecore.Chain.Identifier
  alias Aecore.Contract.Contract
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization

  @contract_key_size 32

  @typedoc "Hash of the tree"
  @type hash :: binary()

  @typedoc "Contracts tree"
  @type contracts_state() :: Trie.t()

  @spec init_empty() :: contracts_state()
  def init_empty do
    PatriciaMerkleTree.new(:contracts)
  end

  @spec insert_contract(contracts_state(), Contract.t()) :: contracts_state()
  def insert_contract(
        contract_tree,
        %Contract{id: %Identifier{value: value}, store: store} = contract
      ) do
    serialized = Serialization.rlp_encode(contract)

    new_contract_tree = PatriciaMerkleTree.insert(contract_tree, value, serialized)
    store_id = Contract.store_id(contract)

    Enum.reduce(store, new_contract_tree, fn {s_key, s_value}, tree_acc ->
      s_tree_key = <<store_id::binary, s_key::binary>>
      PatriciaMerkleTree.insert(tree_acc, s_tree_key, s_value)
    end)
  end

  @spec enter_contract(contracts_state(), Contract.t()) :: contracts_state()
  def enter_contract(
        contract_tree,
        %Contract{id: %Identifier{value: value}, store: store} = contract
      ) do
    serialized = Serialization.rlp_encode(contract)

    updated_contract_tree = PatriciaMerkleTree.enter(contract_tree, value, serialized)
    store_id = Contract.store_id(contract)
    old_contract_store = get_store(store_id, contract_tree)

    update_store(store_id, old_contract_store, store, updated_contract_tree)
  end

  @spec get_contract(contracts_state(), binary()) :: Contract.t()
  def get_contract(contract_tree, key) do
    case PatriciaMerkleTree.lookup(contract_tree, key) do
      {:ok, serialized} ->
        {:ok, deserialized} = Serialization.rlp_decode_anything(serialized)

        identified_id = Identifier.create_identity(key, :contract)

        store_id = Contract.store_id(%{deserialized | id: identified_id})

        %Contract{
          deserialized
          | id: identified_id,
            store: get_store(store_id, contract_tree)
        }

      _ ->
        :none
    end
  end

  @spec root_hash(contracts_state()) :: hash()
  def root_hash(contract_tree) do
    PatriciaMerkleTree.root_hash(contract_tree)
  end

  defp update_store(store_id, old_store, new_store, tree) do
    merged_store = Map.merge(old_store, new_store)

    Enum.reduce(merged_store, tree, fn {s_key, s_value}, tree_acc ->
      # If key exists in new store, we store the new value
      # Otherwise, overwrite with empty tree
      insert_value =
        if Map.has_key?(new_store, s_key) do
          s_value
        else
          <<>>
        end

      s_tree_key = <<store_id::binary, s_key::binary>>
      PatriciaMerkleTree.enter(tree_acc, s_tree_key, insert_value)
    end)
  end

  defp get_store(store_id, tree) do
    keys = PatriciaMerkleTree.all_keys(tree)
    store_id_bit_size = (@contract_key_size + 1) * 8

    Enum.reduce(keys, %{}, fn key, store_acc ->
      with true <- byte_size(key) > @contract_key_size,
           <<tree_store_id::size(store_id_bit_size), s_key::binary>> <- key,
           true <- store_id == <<tree_store_id::size(store_id_bit_size)>> do
        {:ok, s_value} = PatriciaMerkleTree.lookup(tree, key)
        Map.put(store_acc, s_key, s_value)
      else
        _ -> store_acc
      end
    end)
  end
end
