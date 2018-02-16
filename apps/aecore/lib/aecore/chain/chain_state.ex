defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  require Logger
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.ContractTx
  alias Aecore.Structures.ContractProposalTx
  alias Aecore.Structures.ContractSignTx

  @spec calculate_and_validate_chain_state!(list(), map(), integer()) :: map()
  def calculate_and_validate_chain_state!(txs, chain_state, block_height) do
    txs
    |> Enum.reduce(chain_state, fn(transaction, chain_state) ->
      apply_transaction_on_state!(transaction, chain_state, block_height)
    end)
    |> update_chain_state_locked(block_height)
  end

  @spec apply_transaction_on_state!(SignedTx.t(), map(), integer()) :: map()
  def apply_transaction_on_state!(transaction, chain_state, block_height) do
    cond do
      SignedTx.is_coinbase?(transaction) ->
        transaction_in!(chain_state,
                        block_height,
                        transaction.data.to_acc,
                        transaction.data.value,
                        transaction.data.lock_time_block)
      transaction.data.from_acc != nil ->
        if !SignedTx.is_valid?(transaction) do
          throw {:error, "Invalid transaction"}
        end
        chain_state
        |> transaction_out!(block_height,
                            transaction.data.from_acc,
                            -(transaction.data.value + transaction.data.fee),
                            transaction.data.nonce,
                            -1)
        |> transaction_in!(block_height,
                           transaction.data.to_acc,
                           transaction.data.value,
                           transaction.data.lock_time_block)
      true ->
        throw {:error, "Noncoinbase transaction with from_acc=nil"}
    end
  end

  def apply_contract_transaction_on_state!(%SignedTx{data: %ContractProposalTx{}} =
    transaction, chain_state) do
    deduct_from_account_state!(chain_state,
      transaction.contract_hash,
      -transaction.fee,
      transaction.nonce)
  end

  def apply_contract_transaction_on_state!(%SignedTx{data: %ContractSignTx{}} =
    transaction, chain_state) do
    deduct_from_account_state!(chain_state,
      transaction.contract_hash,
      -transaction.fee,
      transaction.nonce)
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

  @spec transaction_in!(map(), integer(), binary(), integer(), integer()) :: map()
  defp transaction_in!(chain_state, block_height, account, value, lock_time_block) do
    account_state = Map.get(chain_state, account, %{balance: 0, nonce: 0, locked: []})
    if block_height <= lock_time_block do
      if value < 0 do
        throw {:error, "Can't lock a negative transaction"}
      end
      new_locked = account_state.locked ++ [%{amount: value, block: lock_time_block}]
      Map.put(chain_state, account, %{account_state | locked: new_locked})
    else
      new_balance = account_state.balance + value
      if new_balance < 0 do
        throw {:error, "Negative balance"}
      end
      Map.put(chain_state, account, %{account_state | balance: new_balance})
    end
  end

  @spec transaction_out!(map(), integer(), binary(), integer(), integer(), integer()) :: map()
  defp transaction_out!(chain_state, block_height, account, value, nonce, lock_time_block) do
    account_state = Map.get(chain_state, account, %{balance: 0, nonce: 0, locked: []})
    if account_state.nonce >= nonce do
      throw {:error, "Nonce too small"}
    end

    chain_state
    |> Map.put(account, %{account_state | nonce: nonce})
    |> transaction_in!(block_height, account, value, lock_time_block)
  end

  defp deduct_from_account_state!(chain_state, account, value, nonce) do
    account_state = Map.get(chain_state, account, %{balance: 0, nonce: 0, locked: []})
    cond do
      account_state.balance + value < 0 ->
        throw {:error, "Negative balance"}
      account_state.nonce >= nonce ->
        throw {:error, "Nonce too small"}
      true ->
        new_balance = account_state.balance + value
        Map.put(chain_state, account, %{account_state | balance: new_balance})
    end
  end
end
