defmodule Aecore.Chain.ChainStateWrapper do
  @moduledoc """
  The module is a wrapper of Aecore.Structures.Chainstate
  """
  alias Aecore.Structures.Chainstate
  alias Aecore.Oracle.Oracle

  @spec calculate_and_validate_chain_state!(list(), Chainstate.t(), non_neg_integer()) ::
          Chainstate.t()
  def calculate_and_validate_chain_state!(txs, chainstate, block_height) do
    Enum.reduce(txs, chainstate, fn tx, chainstate ->
      Chainstate.apply_transaction_on_state!(tx, chainstate, block_height)
    end)
    |> Oracle.remove_expired_oracles(block_height)
    |> Oracle.remove_expired_interaction_objects(block_height)
  end

  @doc """
  Create the root hash of the tree.
  """
  @spec calculate_root_hash(Chainstate.t()) :: binary()
  def calculate_root_hash(chainstate) do
    Chainstate.calculate_root_hash(chainstate)
  end

  def filter_invalid_txs(txs_list, chainstate, block_height) do
    Chainstate.filter_invalid_txs(txs_list, chainstate, block_height)
  end

  @spec calculate_total_tokens(Chainstate.t()) :: non_neg_integer()
  def calculate_total_tokens(chainstate) do
    Chainstate.calculate_total_tokens(chainstate)
  end
end
