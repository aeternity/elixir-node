defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Structures.SignedTx
  alias Aeutil.Serialization
  alias Aeutil.Bits

  require Logger

  @type account_chainstate() ::
          %{binary() =>
            %{balance: integer(),
              locked: [%{amount: integer(), block: integer()}],
              nonce: integer()}}

  @spec calculate_and_validate_chain_state!(list(), account_chainstate(), integer()) :: account_chainstate()
  def calculate_and_validate_chain_state!(txs, chain_state, block_height) do
    txs
    |> Enum.reduce(chain_state, fn(transaction, chain_state) ->
      apply_transaction_on_state!(transaction, chain_state, block_height)
    end)
    |> update_chain_state_locked(block_height)
  end

  @spec apply_transaction_on_state!(SignedTx.t(), account_chainstate(), integer()) :: account_chainstate()
  def apply_transaction_on_state!(transaction, chain_state, block_height) do
    cond do
      SignedTx.is_coinbase?(transaction) ->
        chain_state
        |> apply_transaction_addition!(block_height, transaction)

      transaction.data.from_acc != nil ->
        if !SignedTx.is_valid?(transaction), do: throw {:error, "Invalid transaction"}

        chain_state
        |> apply_transaction_nonce!(transaction)
        |> apply_transaction_deduction!(block_height, transaction)
        |> apply_transaction_addition!(block_height, transaction)

      true ->
        throw {:error, "Noncoinbase transaction with from_acc=nil"}
    end
  end

  @doc """
  Builds a merkle tree from the passed chain state and
  returns the root hash of the tree.
  """
  @spec calculate_chain_state_hash(account_chainstate()) :: binary()
  def calculate_chain_state_hash(chain_state) do
    merkle_tree_data =
      for {account, data} <- chain_state do
        {account, Serialization.pack_binary(data)}
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

  @spec calculate_total_tokens(account_chainstate()) :: integer()
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


  @spec update_chain_state_locked(account_chainstate(), integer()) :: account_chainstate()
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

  @spec bech32_encode(binary()) :: String.t()
  def bech32_encode(bin) do
    Bits.bech32_encode("cs", bin)
  end

  @spec apply_to_state!(account_chainstate(), integer(), binary(), integer(), integer()) :: account_chainstate()
  defp apply_to_state!(chain_state, block_height, account, value, lock_time_block) do
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

  @spec apply_transaction_nonce!(account_chainstate(), SignedTx.t()) :: account_chainstate()
  defp apply_transaction_nonce!(chain_state, transaction) do
    account_state = Map.get(chain_state, transaction.data.from_acc, %{balance: 0, nonce: 0, locked: []})
    if account_state.nonce >= transaction.data.nonce do
      throw {:error, "Nonce too small"}
    end

    chain_state |> Map.put(transaction.data.from_acc, %{account_state | nonce: transaction.data.nonce})
  end

  @spec apply_transaction_deduction!(account_chainstate(), non_neg_integer(), SignedTx.t()) :: account_chainstate()
  defp apply_transaction_deduction!(chain_state, block_height, transaction) do
    chain_state
    |> apply_to_state!(block_height,
                       transaction.data.from_acc,
                       -(transaction.data.value + transaction.data.fee),
                       -1)
  end

  @spec apply_transaction_addition!(account_chainstate(), non_neg_integer(), SignedTx.t()) :: account_chainstate()
  defp apply_transaction_addition!(chain_state, block_height, transaction) do
    chain_state
    |> apply_to_state!(block_height,
                       transaction.data.to_acc,
                       transaction.data.value,
                       transaction.data.lock_time_block)
  end

end
