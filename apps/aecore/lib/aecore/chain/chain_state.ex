defmodule Aecore.Chain.ChainState do
  @moduledoc """
  Module used for calculating the block and chain states.
  The chain state is a map, telling us what amount of tokens each account has.
  """

  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.Account
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aeutil.Serialization
  alias Aeutil.Bits
  alias Aecore.Structures.AccountStateTree
  alias Aecore.Structures.AccountHandler

  require Logger

  @typedoc "Structure of the accounts"
  @type accounts() :: %{Wallet.pubkey() => Account.t()}

  @typedoc "Structure of the chainstate"
  @type chainstate() :: %{:accounts => accounts()}

  @spec calculate_and_validate_chain_state!(list(), chainstate(), integer()) :: chainstate()
  def calculate_and_validate_chain_state!(txs, chainstate, block_height) do
    txs
    |> Enum.reduce(chainstate, fn tx, chainstate ->
      apply_transaction_on_state!(tx, chainstate, block_height)
    end)
  end

  @spec apply_transaction_on_state!(SignedTx.t(), chainstate(), integer()) :: chainstate()
  def apply_transaction_on_state!(%SignedTx{data: data} = tx, chainstate, block_height) do
    cond do
      SignedTx.is_coinbase?(tx) ->
        to_acc_state = AccountHandler.get_account_state(chainstate.accounts, data.payload.to_acc)
        new_to_acc_state = SignedTx.reward(data, to_acc_state)

        new_accounts_state =
          AccountStateTree.put(chainstate.accounts, data.payload.to_acc, new_to_acc_state)

        Map.put(chainstate, :accounts, new_accounts_state)

      data.from_acc != nil ->
        if SignedTx.is_valid?(tx) do
          DataTx.process_chainstate(data, chainstate)
        else
          throw({:error, "Invalid transaction"})
        end
    end
  end

  @doc """
  Create the root hash of the tree.
  """
  @spec calculate_chain_state_hash(chainstate()) :: binary()
  def calculate_chain_state_hash(chainstate) do
    AccountStateTree.root_hash(chainstate.accounts)
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

  @spec calculate_total_tokens(chainstate()) :: non_neg_integer()
  def calculate_total_tokens(%{accounts: accounts}) do
    AccountStateTree.reduce(accounts, 0, fn {k, _v}, acc ->
      acc + AccountHandler.balance(accounts, k)
    end)
  end

  @spec bech32_encode(binary()) :: String.t()
  def bech32_encode(bin) do
    Bits.bech32_encode("cs", bin)
  end
end
