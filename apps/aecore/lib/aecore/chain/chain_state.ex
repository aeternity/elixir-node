defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  require Logger
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.TxData
  alias Aecore.Structures.Header
  alias Aecore.Structures.Account
  alias Aecore.Structures.Voting
  alias Aecore.Keys.Worker, as: Keys

  @voting_create "Voting.create"
  @voting_vote "Voting.vote"

  @spec calculate_and_validate_chain_state!(list(), map(), integer()) :: map()
  def calculate_and_validate_chain_state!(txs, chain_state, block_height) do
    txs
    |> Enum.reduce(chain_state, fn(transaction, chain_state) ->
      apply_tx!(transaction, chain_state, block_height) 
    end)
    |> update_chain_state_locked(block_height)
  end

  @spec apply_tx!(SignedTx.t(), map(), integer()) :: map()
  def apply_tx!(transaction, chain_state, block_height) do
    if SignedTx.is_coinbase?(transaction) do
      apply_fun_on_map(chain_state, transaction.data.to_acc,
                       fn a ->
                         Account.tx_in!(a,
                                        transaction.data,
                                        block_height)
                       end)
    else
      if !SignedTx.is_valid?(transaction) do
        throw {:error, "Invalid transaction"}
      end
      chain_state = apply_fun_on_map(chain_state, transaction.data.from_acc,
                                     fn a -> 
                                       Account.tx_out!(a, 
                                                       transaction.data, 
                                                       block_height) 
                                     end)
      case transaction.data.to_acc do
        @voting_create ->
          chain_state
        @voting_vote ->
          chain_state
        address ->
          case Map.get(chain_state, address, Account.empty()) do
            account = %Account{} -> 
              if !Keys.is_pubkey?(address) do
                throw {:error, "Non-pubkey address"}
              end
              Map.put(chain_state, 
                      address, 
                      Account.tx_in!(account, transaction.data, block_height))
            voting = %Voting{} ->
              Map.put(chain_state,
                      address,
                      Voting.tx_in!(voting, transaction.data, block_height))
            _ ->
              throw {:error, "Invalid contract type on chainstate"}
          end
      end
    end
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
    Enum.reduce(chain_state, %{}, fn({address, object}, acc) ->
      case object do
        account = %Account{} ->
          Map.put(acc, address, Account.update_locked(account, new_block_height))
        other ->
          Map.put(acc, address, other)
      end
    end)
  end

  defp apply_fun_on_map(map, key, function) do
    Map.put(map, key, function.(Map.get(map, key)))
  end

  """
  @spec is_hash?(binary()) :: boolean()
  defp is_hash?(value) do
    byte_size(value) == 32
  end
  """
end
