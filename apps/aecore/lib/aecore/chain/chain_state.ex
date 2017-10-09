defmodule Aecore.Chain.ChainState do

  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  @spec calculate_block_state(%Aecore.Structures.Block{}) :: map()
  def calculate_block_state(block) do
    block_state = %{}
    block_state = for transaction <- block.txs do
      if(transaction.data.from_acc != nil) do
        block_state = update_block_state(block_state,
                                         transaction.data.from_acc,
                                         -transaction.data.value)
        update_block_state(block_state,
                           transaction.data.to_acc,
                           transaction.data.value)
      end
    end

    reduce_map_list(block_state)
  end

  @spec calculate_chain_state(map(), map()) :: map()
  def calculate_chain_state(block_state, chain_state) do
    keys = Map.keys(block_state)
    Map.merge(block_state, chain_state, fn(key, v1, v2) ->
        v1 + v2
      end)
  end

  @spec calculate_chain_state_hash(map()) :: binary()
  def calculate_chain_state_hash(chain_state) do
    merkle_tree_data = []
    merkle_tree_data = for {account, balance} <- chain_state do
      {account, :erlang.term_to_binary(balance)}
    end
    merkle_tree = merkle_tree_data |>
      List.foldl(:gb_merkle_trees.empty, fn(node, merkle_tree)
      -> :gb_merkle_trees.enter(elem(node,0), elem(node,1) , merkle_tree) end)
    :gb_merkle_trees.root_hash(merkle_tree)
  end

  @spec update_block_state(map(), binary(), integer()) :: map()
  defp update_block_state(block_state, account, value) do
    if(!Map.has_key?(block_state, account)) do
      block_state = Map.put(block_state,
                            account, 0)
    end

    Map.put(block_state,
            account,
            block_state[account] + value)
  end

  @spec reduce_map_list(list()) :: map()
  defp reduce_map_list(list) do
    List.foldl(list, %{}, fn(x,acc) ->
        Map.merge(x, acc, fn(key, v1, v2) ->
            v1 + v2
          end)
      end)
  end

end
