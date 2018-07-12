defmodule Aecore.Oracle.OracleStateTree do
  @moduledoc """
  Top level oracle state tree.
  """
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Oracle.Oracle

  @type oracles_state :: %{oracle_tree: Trie.t(), oracle_cache_tree: Trie.t()}
  @dummy_val <<0>>

  @spec init_empty() :: oracles_state()
  def init_empty do
    %{
      oracle_tree: PatriciaMerkleTree.new(:oracles),
      oracle_cache_tree: PatriciaMerkleTree.new(:oracles_cache)
    }
  end

  @spec prune(Chainstate.t(), non_neg_integer()) :: Chainstate.t()
  def prune(chainstate, block_height) do
    {new_oracles_state, new_accounts_state} =
      initialize_deletion({chainstate.oracles, chainstate.accounts}, block_height - 1)

    %{chainstate | oracles: new_oracles_state, accounts: new_accounts_state}
  end

  @spec enter_oracle(oracles_state(), map()) :: oracles_state()
  def enter_oracle(oracles_state, oracle) do
    add_oracle(oracles_state, oracle, :enter)
  end

  @spec insert_oracle(oracles_state(), map()) :: oracles_state()
  def insert_oracle(oracles_state, oracle) do
    add_oracle(oracles_state, oracle, :insert)
  end

  @spec get_oracle(oracles_state(), binary()) :: map()
  def get_oracle(oracles_state, key) do
    get(oracles_state.oracle_tree, key)
  end

  @spec exists_oracle?(oracles_state(), binary()) :: boolean()
  def exists_oracle?(oracles_state, key) do
    exists?(oracles_state, key, :oracle)
  end

  @spec enter_query(oracles_state(), map()) :: oracles_state()
  def enter_query(oracles_state, query) do
    add_query(oracles_state, query, :enter)
  end

  @spec insert_query(oracles_state(), map()) :: oracles_state()
  def insert_query(oracles_state, query) do
    add_query(oracles_state, query, :insert)
  end

  @spec get_query(oracles_state(), binary()) :: map()
  def get_query(oracles_state, key) do
    get(oracles_state.oracle_tree, key)
  end

  @spec exists_query?(oracles_state(), binary()) :: boolean()
  def exists_query?(oracles_state, key) do
    exists?(oracles_state, key, :oracle_query)
  end

  defp initialize_deletion({oracles_state, _accounts_state} = trees, expires) do
    oracles_state.oracle_cache_tree
    |> PatriciaMerkleTree.all_keys()
    |> Enum.reduce(trees, fn cache_key_encoded, new_trees_state ->
      cache_key_encoded
      |> Serialization.cache_key_decode()
      |> filter_expired(expires, cache_key_encoded, new_trees_state)
    end)
  end

  defp filter_expired({expires, data}, expires, cache_key_encoded, trees) do
    {new_oracles_state, new_accounts_state} = delete_expired(data, trees)

    {
      %{
        new_oracles_state
        | oracle_cache_tree: delete(new_oracles_state.oracle_cache_tree, cache_key_encoded)
      },
      new_accounts_state
    }
  end

  defp filter_expired(_, _, _, trees), do: trees

  defp delete_expired({:oracle, oracle_id}, {oracles_state, accounts_state}) do
    {
      %{oracles_state | oracle_tree: delete(oracles_state.oracle_tree, oracle_id)},
      accounts_state
    }
  end

  defp delete_expired({:query, oracle_id, id}, {oracles_state, accounts_state}) do
    query_id = oracle_id <> id
    query = get_query(oracles_state, query_id)

    new_accounts_state = Oracle.refund_sender(query, accounts_state)

    {
      %{oracles_state | oracle_tree: delete(oracles_state.oracle_tree, query_id)},
      new_accounts_state
    }
  end

  defp add_oracle(oracles_state, oracle, how) do
    id = oracle.owner
    expires = oracle.expires
    serialized = Serialization.rlp_encode(oracle, :oracle)

    new_oracle_tree =
      case how do
        :insert ->
          insert(oracles_state.oracle_tree, id, serialized)

        :enter ->
          enter(oracles_state.oracle_tree, id, serialized)
      end

    new_oracle_cache_tree =
      oracles_state
      |> init_pop_stale_cache()
      |> cache_push({:oracle, id}, expires)

    %{oracle_tree: new_oracle_tree, oracle_cache_tree: new_oracle_cache_tree}
  end

  defp add_query(oracles_state, query, how) do
    oracle_id = query.oracle_address

    id =
      OracleQueryTx.id(
        query.sender_address,
        query.sender_nonce,
        oracle_id
      )

    tree_id = oracle_id <> id
    expires = query.expires
    serialized = Serialization.rlp_encode(query, :oracle_query)

    new_oracle_tree =
      case how do
        :insert ->
          insert(oracles_state.oracle_tree, tree_id, serialized)

        :enter ->
          enter(oracles_state.oracle_tree, tree_id, serialized)
      end

    new_oracle_cache_tree =
      oracles_state
      |> init_pop_stale_cache()
      |> cache_push({:query, oracle_id, id}, expires)

    %{oracle_tree: new_oracle_tree, oracle_cache_tree: new_oracle_cache_tree}
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

  defp exists?(oracles_state, key, where) do
    oracles_state
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

  defp which_tree(oracles_state, :oracle), do: oracles_state.oracle_tree
  defp which_tree(oracles_state, :oracle_query), do: oracles_state.oracle_tree
  defp which_tree(oracles_state, _where), do: oracles_state.oracle_tree

  defp cache_push(oracle_cache_tree, key, expires) do
    encoded = Serialization.cache_key_encode(key, expires)
    enter(oracle_cache_tree, encoded, @dummy_val)
  end

  defp init_pop_stale_cache(oracles_state) do
    %{oracle_cache_tree: cache_tree} =
      oracles_state.oracle_cache_tree
      |> PatriciaMerkleTree.all_keys()
      |> Enum.reduce(oracles_state, fn key, new_state ->
        new_cache_tree =
          key
          |> Serialization.cache_key_decode()
          |> pop_stale_cache(key, new_state)

        %{new_state | oracle_cache_tree: new_cache_tree}
      end)

    cache_tree
  end

  defp pop_stale_cache({exp, {:oracle, id}}, stale_cache_key, oracles_state) do
    oracel = get(oracles_state.oracle_tree, id)

    if oracel.expires > exp do
      delete(oracles_state.oracle_cache_tree, stale_cache_key)
    else
      oracles_state.oracle_cache_tree
    end
  end

  defp pop_stale_cache({_exp, {:query, oracle_id, id}}, stale_cache_key, oracles_state) do
    query_id = oracle_id <> id

    case get(oracles_state.oracle_tree, query_id) do
      :none -> delete(oracles_state.oracle_cache_tree, stale_cache_key)
      _query -> oracles_state.oracle_cache_tree
    end
  end
end
