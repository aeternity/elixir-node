defmodule Aecore.Structures.Chainstate do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.Account
  alias Aecore.Structures.AccountStateTree
  alias Aecore.Structures.Chainstate
  alias Aeutil.Bits

  require Logger

  @type tree :: tuple()

  @type t :: %Chainstate{
          accounts: tree()
        }

  defstruct [
    :accounts
  ]

  @spec init :: Chainstate.t()
  def init do
    %Chainstate{
      :accounts => AccountStateTree.init_empty()
    }
  end

  @spec apply_transaction_on_state!(SignedTx.t(), Chainstate.t()) :: Chainstate.t()
  def apply_transaction_on_state!(%SignedTx{data: data} = tx, chainstate) do
    cond do
      SignedTx.is_coinbase?(tx) ->
        receiver_state = Account.get_account_state(chainstate.accounts, data.payload.receiver)

        new_receiver_state = SignedTx.reward(data, receiver_state)

        new_accounts_state =
          AccountStateTree.put(chainstate.accounts, data.payload.receiver, new_receiver_state)

        Map.put(chainstate, :accounts, new_accounts_state)

      data.sender != nil ->
        if SignedTx.is_valid?(tx) do
          DataTx.process_chainstate!(data, chainstate)
        else
          throw({:error, "Invalid transaction"})
        end

      true ->
        throw({:error, "Invalid transaction"})
    end
  end

  @doc """
  Create the root hash of the tree.
  """
  @spec calculate_root_hash(Chainstate.t()) :: binary()
  def calculate_root_hash(chainstate) do
    AccountStateTree.root_hash(chainstate.accounts)
  end

  def filter_invalid_txs(txs_list, chainstate) do
    {valid_txs_list, _} =
      List.foldl(txs_list, {[], chainstate}, fn tx, {valid_txs_list, chainstate_acc} ->
        {valid_chainstate, updated_chainstate} = validate_tx(tx, chainstate_acc)

        if valid_chainstate do
          {valid_txs_list ++ [tx], updated_chainstate}
        else
          {valid_txs_list, chainstate_acc}
        end
      end)

    valid_txs_list
  end

  @spec validate_tx(SignedTx.t(), Chainstate.t()) :: {boolean(), Chainstate.t()}
  defp validate_tx(tx, chainstate) do
    {true, apply_transaction_on_state!(tx, chainstate)}
  catch
    {:error, _} -> {false, chainstate}
  end

  @spec calculate_total_tokens(Chainstate.t()) :: non_neg_integer()
  def calculate_total_tokens(%{accounts: accounts_tree}) do
    AccountStateTree.reduce(accounts_tree, 0, fn {pub_key, _value}, acc ->
      acc + Account.balance(accounts_tree, pub_key)
    end)
  end

  def base58c_encode(bin) do
    Bits.encode58c("bs", bin)
  end

  def base58c_decode(<<"bs$", payload::binary>>) do
    Bits.decode58(payload)
  end

  def base58c_decode(_) do
    {:error, "Wrong data"}
  end
end
