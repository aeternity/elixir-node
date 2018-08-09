defmodule Aecore.Contract.ContractStateTree do

  alias Aecore.Chain.Identifier
  alias Aecore.Contract.Contract
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization

  @type contracts_state() :: Trie.t()

  @spec init_empty() :: contracts_state()
  def init_empty do
    PatriciaMerkleTree.new(:contracts)
  end

  def insert_contract(contract_tree, contract) do
    id = contract.id
    serialized = Serialization.rlp_encode(contract, :contract)

    new_contract_tree = PatriciaMerkleTree.insert(contract_tree, id.value, serialized)
    store_id = Contract.store_id(contract)
    Enum.reduce(contract.store, new_contract_tree, fn {s_key, s_value}, tree_acc ->
      s_tree_key = <<store_id::binary, s_key::binary>>
      PatriciaMerkleTree.insert(tree_acc, s_tree_key, s_value)
    end)
  end

  def enter_contract(contract_tree, contract) do
    id = contract.id
    serialized = Serialization.rlp_encode(contract, :contract)

    updated_contract_tree = PatriciaMerkleTree.enter(contract_tree, id.value, serialized)
    store_id = Contract.store_id(contract)
    old_contract_store = get_store(store_id, contract_tree)

    update_store(store_id, old_contract_store, contract.store, updated_contract_tree)
  end

  def get_contract(contract_tree, key) do
    case PatriciaMerkleTree.lookup(contract_tree, key) do
      {:ok, serialized} ->
        {:ok, deserialized} = Serialization.rlp_decode(serialized)

        {:ok, identified_id} = Identifier.create_identity(key, :contract)
        {:ok, identified_owner} = Identifier.create_identity(deserialized.owner, :account)
        identified_referers =
          Enum.reduce(deserialized.referers, [], fn referer, acc ->
            {:ok, identified_referer} = Identifier.create_identity(referer, :contract)

            [identified_referer | acc]
          end)
          |> Enum.reverse()
        store_id = Contract.store_id(%{deserialized | id: identified_id})

        %{
          deserialized |
          id: identified_id,
          owner: identified_owner,
          store: get_store(store_id, contract_tree),
          referers: identified_referers
        }
      _ ->
        :none

    end
  end

  defp update_store(store_id, old_store, new_store, tree) do
    merged_store = Map.merge(old_store, new_store)
    Enum.reduce(merged_store, tree, fn {s_key, s_value}, tree_acc ->
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

  def get_store(store_id, tree) do
    keys = PatriciaMerkleTree.all_keys(tree)
    Enum.reduce(keys, %{}, fn key, store_acc ->
      cond do
        byte_size(key) >= Application.get_env(:aecore, :aewallet)[:pub_key_size] + 1 ->
          <<tree_store_id::size(272), s_key::binary>> = key
          if store_id == <<tree_store_id::size(272)>> do
            {:ok, s_value} = PatriciaMerkleTree.lookup(tree, key)
            Map.put(store_acc, s_key, s_value)
          else
            store_acc
          end
        true ->
          store_acc
      end
    end)
  end

end
