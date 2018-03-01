defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Structures.SignedTx
  alias Aeutil.Serialization
  alias Aeutil.Bits

  require Logger

  @type account_chainstate() :: %{binary() => map()}

  @spec calculate_and_validate_chain_state!(list(), account_chainstate(), integer()) :: account_chainstate()
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
        address ->
          case Map.get(chain_state, address, Account.empty()) do
            account = %Account{} -> 
              if !Keys.is_pubkey?(address) do
                throw {:error, "Non-pubkey address"}
              end
              Map.put(chain_state, 
                      address, 
                      Account.tx_in!(account, transaction.data, block_height))
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
    Enum.reduce(chain_state, {0, 0, 0}, fn({_account, object}, acc) ->
      case object do
        account = %Account{} ->
          {total_tokens, total_unlocked_tokens, total_locked_tokens} = acc
          locked_tokens =
            Enum.reduce(account.locked, 0, fn(%{amount: amount}, locked_sum) ->
              locked_sum + amount
            end)
          new_total_tokens = total_tokens + account.balance + locked_tokens
          new_total_unlocked_tokens = total_unlocked_tokens + account.balance
          new_total_locked_tokens = total_locked_tokens + locked_tokens
          {new_total_tokens, new_total_unlocked_tokens, new_total_locked_tokens}
        _ ->
          acc
      end
    end)
  end
  
  @spec update_chain_state_locked(account_chainstate(), Header.t()) :: map()
  def update_chain_state_locked(chain_state, header) do
    Enum.reduce(chain_state, %{}, fn({address, object}, acc) ->
      case object do
        account = %Account{} ->
          Map.put(acc, address, Account.update_locked(account, header))
        other ->
          Map.put(acc, address, other)
      end
    end)
  end

  @spec bech32_encode(binary()) :: String.t()
  def bech32_encode(bin) do
    Bits.bech32_encode("cs", bin)
  end

  end

  defp apply_fun_on_map(map, key, function) do
    Map.put(map, key, function.(Map.get(map, key)))
  end

end
