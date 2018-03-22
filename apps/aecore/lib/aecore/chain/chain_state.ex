defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.Account
  alias Aecore.Structures.OracleRegistrationTxData
  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Structures.OracleResponseTxData
  alias Aecore.Oracle.Oracle
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Serialization
  alias Aeutil.Bits

  require Logger

  @typedoc "Structure of the accounts"
  @type accounts() :: %{Wallet.pubkey() => Account.t()}

  @type oracles :: %{
          registered_oracles: registered_oracles(),
          interaction_objects: interaction_objects()
        }

  @type registered_oracles :: %{
          Wallet.pubkey() => %{tx: OracleRegistrationTxData.t(), initial_hash: binary()}
        }

  @type interaction_objects :: %{
          binary() => %{
            query: OracleQueryTxData.t(),
            response: OracleResponseTxData.t(),
            query_initial_hash: binary(),
            response_initial_hash: binary()
          }
        }

  @typedoc "Structure of the chainstate"
  @type chainstate() :: %{:accounts => accounts(), :oracles => oracles()}

  @spec calculate_and_validate_chain_state!(list(), chainstate(), integer()) :: chainstate()
  def calculate_and_validate_chain_state!(txs, chainstate, block_height) do
    updated_chain_state =
      txs
      |> Enum.reduce(chainstate, fn tx, chainstate ->
        apply_transaction_on_state!(tx, chainstate, block_height)
      end)
      |> update_chain_state_locked(block_height)

    updated_chain_state
    |> put_in(
      [:oracles, :registered_oracles],
      Oracle.remove_expired_oracles(
        updated_chain_state.oracles.registered_oracles,
        block_height
      )
    )
    |> put_in(
      [:oracles, :interaction_objects],
      Oracle.remove_expired_interaction_objects(
        updated_chain_state.oracles.interaction_objects,
        block_height,
        updated_chain_state.accounts
      )
    )
  end

  @spec apply_transaction_on_state!(SignedTx.t(), chainstate(), integer()) :: chainstate()
  def apply_transaction_on_state!(%SignedTx{data: data} = tx, chainstate, block_height) do
    cond do
      SignedTx.is_coinbase?(tx) ->
        to_acc_state = Map.get(chainstate.accounts, data.payload.to_acc, Account.empty())
        new_to_acc_state = SignedTx.reward(data, block_height, to_acc_state)
        new_accounts_state = Map.put(chainstate.accounts, data.payload.to_acc, new_to_acc_state)
        Map.put(chainstate, :accounts, new_accounts_state)

      data.from_acc != nil ->
        if SignedTx.is_valid?(tx) do
          DataTx.process_chainstate(data, block_height, chainstate)
        else
          throw({:error, "Invalid transaction"})
        end
    end
  end

  @doc """
  Builds a merkle tree from the passed chain state and
  returns the root hash of the tree.
  """
  @spec calculate_chain_state_hash(chainstate()) :: binary()
  def calculate_chain_state_hash(chainstate) do
    merkle_tree_data =
      for {account, data} <- chainstate.accounts do
        {account, Serialization.pack_binary(data)}
      end

    if Enum.empty?(merkle_tree_data) do
      <<0::256>>
    else
      merkle_tree =
        List.foldl(merkle_tree_data, :gb_merkle_trees.empty(), fn node, merkle_tree ->
          :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree)
        end)

      :gb_merkle_trees.root_hash(merkle_tree)
    end
  end

  def filter_invalid_txs(txs_list, chainstate, block_height) do
    {valid_txs_list, _} =
      List.foldl(txs_list, {[], chainstate}, fn tx, {valid_txs_list, chainstate_acc} ->
        {valid_chainstate, updated_chainstate} = validate_tx(tx, chainstate_acc, block_height)

        if valid_chainstate do
          {valid_txs_list ++ [tx], updated_chainstate}
        else
          {valid_txs_list, chainstate_acc}
        end
      end)

    valid_txs_list
  end

  @spec validate_tx(SignedTx.t(), chainstate(), integer()) :: {boolean(), chainstate()}
  defp validate_tx(tx, chainstate, block_height) do
    try do
      {true, apply_transaction_on_state!(tx, chainstate, block_height)}
    catch
      {:error, _} -> {false, chainstate}
    end
  end

  @spec calculate_total_tokens(chainstate()) :: {integer(), integer(), integer()}
  def calculate_total_tokens(%{accounts: accounts}) do
    Enum.reduce(accounts, {0, 0, 0}, fn {_account, state}, acc ->
      {total_tokens, total_unlocked_tokens, total_locked_tokens} = acc

      locked_tokens =
        Enum.reduce(state.locked, 0, fn %{amount: amount}, locked_sum ->
          locked_sum + amount
        end)

      new_total_tokens = total_tokens + state.balance + locked_tokens
      new_total_unlocked_tokens = total_unlocked_tokens + state.balance
      new_total_locked_tokens = total_locked_tokens + locked_tokens
      {new_total_tokens, new_total_unlocked_tokens, new_total_locked_tokens}
    end)
  end

  @spec update_chain_state_locked(chainstate(), Header.t()) :: chainstate()
  def update_chain_state_locked(%{accounts: accounts} = chainstate, header) do
    updated_accounts =
      Enum.reduce(accounts, %{}, fn {address, state}, acc ->
        Map.put(acc, address, Account.update_locked(state, header))
      end)

    Map.put(chainstate, :accounts, updated_accounts)
  end

  @spec bech32_encode(binary()) :: String.t()
  def bech32_encode(bin) do
    Bits.bech32_encode("cs", bin)
  end
end
