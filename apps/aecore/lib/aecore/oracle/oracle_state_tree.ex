defmodule Aecore.Oracle.OracleStateTree do
  @moduledoc """
  Top level oracle state tree.
  """
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias Aecore.Oracle.Tx.OracleQueryTx

  @type oracles_state :: %{otree: Trie.t(), ctree: Trie.t()}
  @dummy_val <<0>>

  @spec init_empty() :: oracles_state()
  def init_empty do
    %{otree: PatriciaMerkleTree.new(:oracles), ctree: PatriciaMerkleTree.new(:oracles_cache)}
  end

  @spec prune(oracles_state(), non_neg_integer()) :: oracles_state()
  def prune(tree, block_height) do
    expired_oracles = get_expired_oracle_ids(tree, block_height - 1)
    initialize_deletion(tree, expired_oracles)
  end

  @spec enter_oracle(oracles_state(), map()) :: oracles_state()
  def enter_oracle(tree, oracle) do
    add_oracle(tree, oracle, :enter)
  end

  @spec insert_oracle(oracles_state(), map()) :: oracles_state()
  def insert_oracle(tree, oracle) do
    add_oracle(tree, oracle, :insert)
  end

  @spec get_oracle(oracles_state(), binary()) :: map()
  def get_oracle(tree, key) do
    get(tree.otree, key)
  end

  @spec lookup_oracle?(oracles_state(), binary()) :: boolean()
  def lookup_oracle?(tree, key) do
    lookup?(tree, key, :oracle)
  end

  @spec enter_query(oracles_state(), map()) :: oracles_state()
  def enter_query(tree, query) do
    add_query(tree, query, :enter)
  end

  @spec insert_query(oracles_state(), map()) :: oracles_state()
  def insert_query(tree, query) do
    add_query(tree, query, :insert)
  end

  @spec get_query(oracles_state(), binary()) :: map()
  def get_query(tree, key) do
    get(tree.otree, key)
  end

  @spec lookup_query?(oracles_state(), binary()) :: boolean()
  def lookup_query?(tree, key) do
    lookup?(tree, key, :oracle_query)
  end

  defp initialize_deletion(tree, expired_oracles) do
    expired_cache = get_expired_cache_ids(tree.ctree, expired_oracles)

    new_map_tree =
      Enum.reduce(expired_oracles, tree, fn {account_pubkey, _expires}, acc_tree ->
        %{acc_tree | otree: delete(acc_tree.otree, account_pubkey)}
      end)

    Enum.reduce(expired_cache, new_map_tree, fn cache, acc_tree ->
      %{acc_tree | ctree: delete(acc_tree.ctree, cache)}
    end)
  end

  defp add_oracle(tree, oracle, how) do
    id = oracle.owner
    expires = oracle.expires
    serialized = Serialization.rlp_encode(oracle, :oracle)

    new_otree =
      case how do
        :insert ->
          insert(tree.otree, id, serialized)

        :enter ->
          enter(tree.otree, id, serialized)
      end

    new_ctree = cache_push(tree.ctree, {:oracle, id}, expires)
    %{otree: new_otree, ctree: new_ctree}
  end

  defp add_query(tree, query, how) do
    oracle_id = query.oracle_address

    id =
      OracleQueryTx.id(
        query.sender_address,
        query.sender_nonce,
        oracle_id
      )

    tree_id = oracle_id <> id
    expires = query.sender_address
    serialized = Serialization.rlp_encode(query, :oracle_query)

    new_otree =
      case how do
        :insert ->
          insert(tree.otree, tree_id, serialized)

        :enter ->
          enter(tree.otree, tree_id, serialized)
      end

    new_ctree = cache_push(tree.ctree, {:query, oracle_id, id}, expires)
    %{otree: new_otree, ctree: new_ctree}
  end

  defp insert(tree, key, value) do
    PatriciaMerkleTree.enter(tree, key, value)
  end

  defp enter(tree, key, value) do
    PatriciaMerkleTree.enter(tree, key, value)
  end

  defp delete(tree, key) do
    PatriciaMerkleTree.delete(tree, key)
  end

  defp lookup?(tree, key, where) do
    tree
    |> which_tree(where)
    |> get(key) !== :none
  end

  defp get(tree, key) do
    case PatriciaMerkleTree.lookup(tree, key) do
      {:ok, serialized} ->
        {:ok, deserialized} = Serialization.rlp_decode(serialized)
        deserialized

      _ ->
        :none
    end
  end

  defp which_tree(tree, :oracle), do: tree.otree
  defp which_tree(tree, :oracle_query), do: tree.otree
  defp which_tree(tree, _where), do: tree.otree

  defp get_expired_oracle_ids(tree, block_height) do
    tree.otree
    |> PatriciaMerkleTree.all_keys()
    |> Enum.reduce([], fn account_pubkey, acc ->
      expires = get_oracle(tree, account_pubkey).expires

      if expires == block_height do
        [{account_pubkey, expires}] ++ acc
      else
        acc
      end
    end)
  end

  defp get_expired_cache_ids(_tree, expired_oracles) do
    for {account_pubkey, expires_at} <- expired_oracles do
      cache_key_encode({:oracle, account_pubkey}, expires_at)
    end
  end

  defp cache_push(ctree, key, expires) do
    encoded = cache_key_encode(key, expires)
    enter(ctree, encoded, @dummy_val)
  end

  defp cache_key_encode(key, expires) do
    :sext.encode({expires, key})
  end
end
