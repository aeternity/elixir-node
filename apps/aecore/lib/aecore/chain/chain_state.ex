defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Keys.Worker, as: Keys

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
              update_block_state(block_state, transaction.data.from_acc,
                                 -(transaction.data.value + transaction.data.fee),
                                 transaction.data.nonce)

            true ->
              block_state
          end

        update_block_state(updated_block_state, transaction.data.to_acc, transaction.data.value, 0)
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

  @spec calculate_total_tokens(map()) :: integer()
  def calculate_total_tokens(chain_state) do
    chain_state |>
      Enum.map(fn{_account, data} -> data.balance end) |>
      Enum.sum()
  end

  @spec validate_chain_state(map()) :: boolean()
  def validate_chain_state(chain_state) do
    chain_state |>
      Enum.map(fn{_account, data} -> Map.get(data, :balance, 0) >= 0 end) |>
      Enum.all?()
  end

  @spec add_fees_to_block_state(list(), map()) :: map()
  def add_fees_to_block_state(txs, block_state) do
    pubkey = elem(Keys.pubkey(), 1)
    total_fees = List.foldl(txs, 0, fn(tx, acc) ->
        acc + tx.data.fee
      end)

    cond do
      !Map.has_key?(block_state, pubkey) ->
        Map.put(block_state, pubkey, %{balance: total_fees, nonce: 0})

      true ->
        current_pubkey_block_state = Map.get(block_state, pubkey)
        new_pubkey_block_state = %{balance: current_pubkey_block_state.balance + total_fees,
                                   nonce: current_pubkey_block_state.nonce}
        Map.replace(block_state, pubkey, new_pubkey_block_state)
    end
  end

  @spec update_block_state(map(), binary(), integer(), integer()) :: map()
  defp update_block_state(block_state, account, value, nonce) do
    block_state_filled_empty =
      cond do
        !Map.has_key?(block_state, account) ->
          Map.put(block_state, account, %{balance: 0, nonce: 0})

        true ->
          block_state
      end

    new_nonce = cond do
      block_state_filled_empty[account].nonce < nonce ->
        nonce

      true ->
        block_state_filled_empty[account].nonce
    end

    new_account_state = %{balance: block_state_filled_empty[account].balance + value,
                          nonce:   new_nonce}
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

      %{balance: v1.balance + v2.balance, nonce: new_nonce}
    end)
  end
end
