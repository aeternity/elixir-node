defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  require Logger

  @doc """
  Calculates the balance of each account mentioned
  in the transactions a single block, returns a map with the
  accounts as key and their balance as value.
  """
  @spec calculate_block_state(list(), integer()) :: map()
  def calculate_block_state(txs, latest_block_height) do
    empty_block_state = %{}

    block_state = for transaction <- txs do
        updated_block_state =
          cond do
            transaction.data.from_acc != nil ->
              update_block_state(empty_block_state, transaction.data.from_acc,
                                 -(transaction.data.value + transaction.data.fee),
                                 transaction.data.nonce, transaction.data.lock_time_block, false)

            true ->
              empty_block_state
          end

        add_to_locked = latest_block_height + 1 <= transaction.data.lock_time_block

        update_block_state(updated_block_state, transaction.data.to_acc, transaction.data.value,
                           0, transaction.data.lock_time_block, add_to_locked)
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
    merge_states(block_state, chain_state)
  end

  @doc """
  Builds a merkle tree from the passed chain state and
  returns the root hash of the tree.
  """
  @spec calculate_chain_state_hash(map()) :: binary()
  def calculate_chain_state_hash(chain_state) do
    merkle_tree_data =
      for {account, data} <- chain_state do
        {account, :erlang.term_to_binary(data)}
      end

    if Enum.empty?(merkle_tree_data) do
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

  @spec calculate_total_tokens(map()) :: integer()
  def calculate_total_tokens(chain_state) do
    Enum.reduce(chain_state, {0, 0, 0}, fn({_account, data}, acc) ->
      {total_tokens, total_unlocked_tokens, total_locked_tokens} = acc
      locked_tokens =
        Enum.reduce(data.locked, 0, fn(%{amount: amount}, locked_sum) ->
          locked_sum + amount
         end)
      new_total_tokens = total_tokens + data.balance + locked_tokens
      new_total_unlocked_tokens = total_unlocked_tokens + data.balance
      new_total_locked_tokens = total_locked_tokens + locked_tokens

      {new_total_tokens, new_total_unlocked_tokens, new_total_locked_tokens}
    end)
  end

  @spec validate_chain_state(map()) :: boolean()
  def validate_chain_state(chain_state) do
    chain_state
    |> Enum.map(fn{_account, data} -> Map.get(data, :balance, 0) >= 0 end)
    |> Enum.all?()
  end

  @spec update_chain_state_locked(map(), integer()) :: map()
  def update_chain_state_locked(chain_state, new_block_height) do
    Enum.reduce(chain_state, %{}, fn({account, %{balance: balance, nonce: nonce, locked: locked}}, acc) ->
      {unlocked_amount, updated_locked} =
          Enum.reduce(locked, {0, []}, fn(%{amount: amount, block: lock_time_block}, {amount_update_value, updated_locked}) ->
            cond do
              lock_time_block > new_block_height ->
                {amount_update_value, updated_locked ++ [%{amount: amount, block: lock_time_block}]}
              lock_time_block == new_block_height ->
                {amount_update_value + amount, updated_locked}

              true ->
                Logger.error(fn ->
                  "Update chain state locked:
                   new block height (#{new_block_height}) greater than lock time block (#{lock_time_block})"
                end)

                {amount_update_value, updated_locked}
            end
          end)

        Map.put(acc, account, %{balance: balance + unlocked_amount, nonce: nonce, locked: updated_locked})
      end)
  end

  @spec update_block_state(map(), binary(), integer(), integer(), integer(), boolean()) :: map()
  defp update_block_state(block_state, account, value, nonce, lock_time_block, add_to_locked) do
    block_state_filled_empty =
      cond do
        !Map.has_key?(block_state, account) ->
          Map.put(block_state, account, %{balance: 0, nonce: 0, locked: []})

        true ->
          block_state
      end

    new_balance = if(add_to_locked) do
      block_state_filled_empty[account].balance
    else
      block_state_filled_empty[account].balance + value
    end

    new_nonce = cond do
      block_state_filled_empty[account].nonce < nonce ->
        nonce
      true ->
        block_state_filled_empty[account].nonce
      end

    new_locked = if(add_to_locked) do
      block_state_filled_empty[account].locked ++ [%{amount: value, block: lock_time_block}]
    else
      block_state_filled_empty[account].locked
    end

    new_account_state = %{balance: new_balance,
                          nonce:   new_nonce,
                          locked:  new_locked}

    Map.put(block_state_filled_empty, account, new_account_state)
  end

  @spec reduce_map_list(list()) :: map()
  defp reduce_map_list(list) do
    List.foldl(list, %{}, fn x, acc ->
      merge_states(x, acc)
    end)
  end

  @spec merge_states(map(), map()) :: map()
  defp merge_states(new_state, destination_state) do
    Map.merge(new_state, destination_state, fn _key, v1, v2 ->
      new_nonce = cond do
        v1.nonce > v2.nonce ->
          v1.nonce
        v2.nonce > v1.nonce ->
          v2.nonce

        true ->
          v1.nonce
      end

      %{balance: v1.balance + v2.balance,
        nonce: new_nonce,
        locked: v1.locked ++ v2.locked}
    end)
  end
end
