defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  @doc """
  Calculates the balance of each account mentioned
  in the transactions a single block, returns a map with the
  accounts as key and their balance as value.
  """
  @spec calculate_block_state(list()) :: map()
  def calculate_block_state(txs) do
    block_state = %{}

    block_state =
      for transaction <- txs do
        updated_block_state =
          cond do
            transaction.data.from_acc != nil ->
              update_block_state(block_state, transaction.data.from_acc, -transaction.data.value)

            true ->
              block_state
          end

        update_block_state(updated_block_state, transaction.data.to_acc, transaction.data.value)
      end

    reduce_map_list(block_state)
  end

  @doc """
  Calculates the state of the chain with the new block added
  to the current state, returns a map with the
  accounts as key and their balance as value.
  """
  @spec calculate_chain_state(map(), map()) :: map()
  def calculate_chain_state(block_state, chain_state) do
    Map.merge(block_state, chain_state, fn _key, v1, v2 ->
      v1 + v2
    end)
  end

  @doc """
  Builds a merkle tree from the passed chain state and
  returns the root hash of the tree.
  """
  @spec calculate_chain_state_hash(map()) :: binary()
  def calculate_chain_state_hash(chain_state) do
    merkle_tree_data =
      for {account, balance} <- chain_state do
        {account, :erlang.term_to_binary(balance)}
      end

    if length(merkle_tree_data) == 0 do
      <<0::256>>
    else
      merkle_tree =
        merkle_tree_data
        |> List.foldl(:gb_merkle_trees.empty(), fn node, merkle_tree ->
             :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree)
           end)

      :gb_merkle_trees.root_hash(merkle_tree)
    end
  end

  def calculate_total_tokens(chain_state) do
    chain_state |>
      Enum.map(fn{_account, balance} -> balance end) |>
      Enum.sum()
  end

  @spec update_block_state(map(), binary(), integer()) :: map()
  defp update_block_state(block_state, account, value) do
    block_state_filled_empty =
      cond do
        !Map.has_key?(block_state, account) ->
          Map.put(block_state, account, 0)

        true ->
          block_state
      end

    Map.put(block_state_filled_empty, account, block_state_filled_empty[account] + value)
  end

  @spec reduce_map_list(list()) :: map()
  defp reduce_map_list(list) do
    List.foldl(list, %{}, fn x, acc ->
      Map.merge(x, acc, fn _key, v1, v2 ->
        v1 + v2
      end)
    end)
  end
end
