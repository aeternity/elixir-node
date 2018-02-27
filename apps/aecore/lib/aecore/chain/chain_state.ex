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

  @typedoc "Public key representing an account"
  @type pubkey() :: binary()

  @typedoc "State of an account"
  @type acc_state() :: %{balance: integer(),
                         locked: [%{amount: integer(), block: integer()}],
                         nonce: integer()}

  @typedoc "Structure of the accounts"
  @type accounts() :: %{pubkey() => acc_state()}

  @typedoc "Structure of the chainstate"
  @type chainstate() :: map()

  @spec calculate_and_validate_chain_state!(list(), chainstate(), integer()) :: chainstate()
  def calculate_and_validate_chain_state!(txs, chain_state, block_height) do
    txs
    |> Enum.reduce(chain_state, fn(tx, chain_state) ->
      apply_transaction_on_state!(tx, chain_state, block_height)
    end)
    |> update_chain_state_locked(block_height)
  end

  @spec apply_transaction_on_state!(SignedTx.t(), chainstate(), integer()) :: chainstate()
  def apply_transaction_on_state!(%SignedTx{data: data} = tx, chainstate, block_height) do

    cond do
      SignedTx.is_coinbase?(tx) ->
        to_acc_state = Map.get(chainstate.accounts, data.payload.to_acc, %{balance: 0, nonce: 0, locked: []})
        new_to_acc_state = SignedTx.reward(data, block_height, to_acc_state)
        new_accounts_state = Map.put(chainstate.accounts, data.payload.to_acc, new_to_acc_state)
        Map.put(chainstate, :accounts, new_accounts_state)

      data.from_acc != nil ->
        if SignedTx.is_valid?(tx) do
          DataTx.process_chainstate(data, block_height, chainstate)
        else
          throw {:error, "Invalid transaction"}
        end

      true ->
        throw {:error, "Noncoinbase transaction with from_acc=nil"}
    end
  end

  @spec update_chain_state_locked(chainstate(), integer()) :: chainstate()
  def update_chain_state_locked(%{accounts: accounts} = chainstate, new_block_height) do
    accounts =
      Enum.reduce(accounts, %{}, fn({pubkey, account_state}, acc) ->
        {unlocked_amount, updated_locked} =
          Enum.reduce(account_state.locked, {0, []}, fn(locked, {amount_update_value, updated_locked}) ->
            cond do
              locked.block > new_block_height ->
                {amount_update_value, updated_locked ++ [%{amount: locked.amount, block: locked.block}]}

              locked.block == new_block_height ->
                {amount_update_value + locked.amount, updated_locked}

              true ->
                Logger.error(fn ->
                  "Update chain state locked:
                  new block height (#{new_block_height}) greater than lock time block (#{locked.block})"
                end)
                {amount_update_value, updated_locked}
            end
          end)
        Map.put(acc, pubkey, %{balance: account_state.balance + unlocked_amount,
                               nonce: account_state.nonce,
                               locked: updated_locked})
      end)
      Map.put(chainstate, :accounts, accounts)
  end

  @doc """
  Builds a merkle tree from the passed chain state and
  returns the root hash of the tree.
  """
  @spec calculate_chain_state_hash(chainstate()) :: binary()
  def calculate_chain_state_hash(%{accounts: accounts} = chainstate) do
    merkle_tree_data =
      for {account, data} <- accounts do
        {account, Serialization.pack_binary(data)}
      end

    if Enum.empty?(merkle_tree_data) do
      <<0::256>>
    else
      merkle_tree =
        List.foldl(merkle_tree_data, :gb_merkle_trees.empty(), fn(node, merkle_tree) ->
          :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree)
        end)
      :gb_merkle_trees.root_hash(merkle_tree)
    end
  end


  @spec calculate_total_tokens(chainstate()) :: {integer(), integer(), integer()}
  def calculate_total_tokens(%{accounts: accounts}) do
    Enum.reduce(accounts, {0, 0, 0}, fn({_pubkey, acc_state}, acc) ->
      {total_tokens, total_unlocked_tokens, total_locked_tokens} = acc
      locked_tokens =
        Enum.reduce(acc_state.locked, 0, fn(%{amount: amount}, locked_sum) ->
          locked_sum + amount
         end)
      new_total_tokens = total_tokens + acc_state.balance + locked_tokens
      new_total_unlocked_tokens = total_unlocked_tokens + acc_state.balance
      new_total_locked_tokens = total_locked_tokens + locked_tokens

      {new_total_tokens, new_total_unlocked_tokens, new_total_locked_tokens}
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

  @spec validate_tx(SignedTx.t(), chainstate(), integer()) :: {boolean(), map()}
  defp validate_tx(tx, chainstate, block_height) do
    try do
      {true, apply_transaction_on_state!(tx, chainstate, block_height)}
    catch
      {:error, _} -> {false, chainstate}
    end
  end

end
