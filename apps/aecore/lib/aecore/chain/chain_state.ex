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
    block_state = for transaction <- txs do
      if(transaction.data.from_acc != nil) do
        block_state = update_block_state(block_state,
                                         transaction.data.from_acc,
                                         -transaction.data.value)
      end
      update_block_state(block_state,
                         transaction.data.to_acc,
                         transaction.data.value)
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
    keys = Map.keys(block_state)
    Map.merge(block_state, chain_state, fn(key, v1, v2) ->
        v1 + v2
      end)
  end

  @doc """
  Builds a merkle tree from the passed chain state and
  returns the root hash of the tree.
  """
  @spec calculate_chain_state_hash(map()) :: binary()
  def calculate_chain_state_hash(chain_state) do
    merkle_tree_data = []
    merkle_tree_data = for {account, balance} <- chain_state do
      {account, :erlang.term_to_binary(balance)}
    end
    if(length(merkle_tree_data) == 0) do
      <<0::256>>
    else
      merkle_tree = merkle_tree_data |>
        List.foldl(:gb_merkle_trees.empty, fn(node, merkle_tree)
        -> :gb_merkle_trees.enter(elem(node,0), elem(node,1) , merkle_tree) end)
      :gb_merkle_trees.root_hash(merkle_tree)
    end
  end

  def calculate_total_tokens(chain_state) do
    total_amount = 0
    total_amount = for {_account, balance} <- chain_state do
      total_amount + balance
    end
    Enum.at(total_amount, 0)
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
