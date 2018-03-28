defmodule Aecore.Chain.ChainState do
  @moduledoc """
  The module is a wrapper of Aecore.Structures.Chainstate
  """
  alias Aecore.Structures.Chainstate

  @spec calculate_and_validate_chain_state!(list(), Chainstate.t()) :: Chainstate.t()
  def calculate_and_validate_chain_state!(txs, chainstate) do
    txs
    |> Enum.reduce(chainstate, fn tx, chainstate ->
      Chainstate.apply_transaction_on_state!(tx, chainstate)
    end)
  end

  @doc """
  Create the root hash of the tree.
  """
  @spec calculate_root_hash(Chainstate.t()) :: binary()
  def calculate_root_hash(chainstate) do
    Chainstate.calculate_root_hash(chainstate)
  end

  def filter_invalid_txs(txs_list, chainstate) do
    Chainstate.filter_invalid_txs(txs_list, chainstate)
  end

  @spec calculate_total_tokens(Chainstate.t()) :: non_neg_integer()
  def calculate_total_tokens(chainstate) do
    Chainstate.calculate_total_tokens(chainstate)
  end
end
