defmodule Aecore.Chain.Chainstate do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate
  alias Aeutil.Bits
  alias Aecore.Oracle.Oracle

  require Logger

  @type t :: %Chainstate{
          accounts: AccountStateTree.accounts_state(),
          oracles: Oracle.oracles()
        }

  defstruct [
    :accounts,
    :oracles
  ]

  @spec init :: Chainstate.t()
  def init do
    %Chainstate{
      :accounts => AccountStateTree.init_empty(),
      :oracles => %{registered_oracles: %{}, interaction_objects: %{}}
    }
  end

  @spec calculate_and_validate_chain_state!(list(), Chainstate.t(), non_neg_integer()) ::
          Chainstate.t()
  def calculate_and_validate_chain_state!(txs, chainstate, block_height) do
    txs
    |> Enum.reduce(chainstate, fn tx, chainstate ->
      apply_transaction_on_state!(chainstate, block_height, tx)
    end)
    |> Oracle.remove_expired_oracles(block_height)
    |> Oracle.remove_expired_interaction_objects(block_height)
  end

  @spec apply_transaction_on_state!(Chainstate.t(), non_neg_integer(), SignedTx.t()) :: Chainstate.t()
  def apply_transaction_on_state!(chainstate, block_height, tx) do
    if !SignedTx.is_valid?(tx) do
      throw({:error, "Invalid transaction"})
    end

    SignedTx.process_chainstate!(chainstate, block_height, tx)
  end

  @doc """
  Create the root hash of the tree.
  """
  @spec calculate_root_hash(Chainstate.t()) :: binary()
  def calculate_root_hash(chainstate) do
    AccountStateTree.root_hash(chainstate.accounts)
  end

  def filter_invalid_txs(txs_list, chainstate, block_height) do
    {valid_txs_list, _} =
      List.foldl(txs_list,
                 {[], chainstate},
                 fn tx, {valid_txs_list, chainstate_acc} ->
        {valid_chainstate, updated_chainstate} = validate_tx(tx, chainstate_acc, block_height)

        if valid_chainstate do
          {[tx | valid_txs_list], updated_chainstate}
        else
          {valid_txs_list, chainstate_acc}
        end
      end)

    Enum.reverse(valid_txs_list)
  end

  @spec validate_tx(SignedTx.t(), Chainstate.t(), non_neg_integer()) ::
          {boolean(), Chainstate.t()}
  defp validate_tx(tx, chainstate, block_height) do
    try do
      {true, apply_transaction_on_state!(chainstate, block_height, tx)}
    catch
      {:error, _} -> {false, chainstate}
    end
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
