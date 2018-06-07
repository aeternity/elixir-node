defmodule Aecore.Oracle.OracleStateTree do
  @moduledoc """
  Top level oracle state tree.
  """
  alias Aecore.Oracle.Oracle
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias Aecore.Oracle.Tx.{OracleRegistrationTx, OracleQueryTx}
  alias Aecore.Wallet.Worker, as: Wallet

  #  @type oracles_state :: Trie.t()
  @type oracles_state :: %{otree: Trie.t(), ctree: Trie.t()}
  @type hash :: binary()

  @dummy_val <<0>>

  @spec init_empty() :: oracles_state()
  def init_empty do
    %{otree: PatriciaMerkleTree.new(:oracles), ctree: PatriciaMerkleTree.new(:oracles_cache)}
  end

  def prune(tree, block_height) do
    # # [{account_pubkey, expires}]
    # expired_oracles = get_expited_oracle_ids(tree, block_height - 1)
    # initialize_deletion(tree, expired_oracles)
    tree
  end

  defp initialize_deletion(tree, expired_oracles) do
    # TODO -> Does not cover full functionality
    #    expired_cache = get_expited_cache_ids(expired_oracles)
    Enum.reduce(expired_oracles, tree, fn {account_pubkey, expires} = exp, acc_tree ->
      new_otree = delete(acc_tree.otree, account_pubkey)
    end)
  end

  ### ===================================================================
  ### Oracles API
  ### ===================================================================
  def enter_oracle(tree, oracle) do
    add_oracle(tree, oracle, :enter)
  end

  def insert_oracle(tree, oracle) do
    add_oracle(tree, oracle, :insert)
  end

  def get_oracle(tree, key) do
    get(tree.otree, key)
  end

  def lookup_oracle?(tree, key) do
    lookup?(tree, key, :oracle)
  end

  ### ===================================================================
  ### Query / Interaction objects  API
  ### ===================================================================
  def enter_query(tree, query) do
    add_query(tree, query, :enter)
  end

  def insert_query(tree, query) do
    add_query(tree, query, :insert)
  end

  def get_query(tree, key) do
    get(tree.otree, key)
  end

  def lookup_query?(tree, key) do
    lookup?(tree, key, :oracle_query)
  end

  ### ===================================================================
  ### Internal functions
  ### ===================================================================
  ### Oracles ===========================================================
  defp add_oracle(tree, oracle, how) do
    id = Oracle.get_owner(oracle)
    expires = Oracle.get_expires(oracle)
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

  ### Querys ===========================================================
  defp add_query(tree, query, how) do
    oracle_id = OracleQueryTx.get_oracle_address(query)

    id =
      OracleQueryTx.id(
        OracleQueryTx.get_sender_address(query),
        OracleQueryTx.get_sender_nonce(query),
        oracle_id
      )

    tree_id = oracle_id <> id

    expires = OracleQueryTx.get_expires(query)
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

  ### PMT ==============================================================

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

  ### Helper functions ================================================

  defp get_expited_oracle_ids(tree, block_height) do
    PatriciaMerkleTree.all_keys(tree.otree)
    |> Enum.reduce([], fn account_pubkey, acc ->
      expires = get_oracle(tree, account_pubkey).expires

      if expires == block_height do
        [{account_pubkey, expires}] ++ acc
      else
        acc
      end
    end)
  end

  defp get_expited_cache_ids(tree, block_height) do
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

  defp cache_key_decode() do
    :not_implemented
  end
end
