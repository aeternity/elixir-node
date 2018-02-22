defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.DataTx
  alias Aeutil.Serialization

  require Logger

  @type account_chainstate() ::
          %{binary() =>
            %{balance: integer(),
              locked: [%{amount: integer(), block: integer()}],
              nonce: integer()}}

  @spec calculate_and_validate_chain_state!(list(), account_chainstate(), integer()) ::  account_chainstate()
  def calculate_and_validate_chain_state!(txs, chain_state, block_height) do
    txs
    |> Enum.reduce(chain_state, fn(tx, chain_state) ->
      validate_tx(tx, chain_state, block_height)
    end)
    |> update_chain_state_locked(block_height)
  end

  @spec apply_transaction_on_state!(SignedTx.t(), account_chainstate(), integer()) :: account_chainstate()
  def apply_transaction_on_state!(%SignedTx{data: data} = tx, chain_state, block_height) do
    account = data.payload.to_acc
    account_state = Map.get(chainstate, account, %{balance: 0, nonce: 0, locked: []})

    cond do
      SignedTx.is_coinbase?(tx) ->
        new_accaunt_state = SignedTx.reward(data, account_state, block_height)
        Map.put(chain_state, account, new_account_state)


      data.from_acc != nil ->
        if SignedTx.is_valid?(tx) do
          new_account_state = DataTx.process_chainstate(data, account_state, block_height)
          Map.put(chain_state, account, new_account_state)
        else
          throw {:error, "Invalid transaction"}
        end

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

  def filter_invalid_txs(txs_list, chain_state, block_height) do
    {valid_txs_list, _} = List.foldl(
      txs_list,
      {[], chain_state},
      fn (tx, {valid_txs_list, chain_state_acc}) ->
        {valid_chain_state, updated_chain_state} = validate_tx(tx, chain_state_acc, block_height)

        if valid_chain_state do
          {valid_txs_list ++ [tx], updated_chain_state}
        else
          {valid_txs_list, chain_state_acc}
        end

      end)

    valid_txs_list
  end

  @spec validate_tx(SignedTx.t(), ChainState.account_chainstate(), integer()) :: {boolean(), map()}
  defp validate_tx(tx, chain_state, block_height) do
    try do
      case tx do
        %SignedTx{data: %SpendTx{}} ->
          {true, apply_transaction_on_state!(tx, chain_state, block_height)}
        %SignedTx{data: %DataTx{}} ->
          {true, deduct_from_account_state!(chain_state,tx.data.from_acc,
                                                       tx.data.fee,
                                                       tx.data.nonce)}
      end
    catch
      {:error, _} -> {false, chain_state}
    end
  end

end
