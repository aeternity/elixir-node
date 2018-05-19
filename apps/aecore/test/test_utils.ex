defmodule TestUtils do
  @moduledoc """
  Helper module for retrieving the chainstate
  """

  use ExUnit.Case

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.Account
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Persistence.Worker, as: Persistence

  def get_accounts_chainstate do
    Chain.chain_state().accounts
  end

  def assert_balance(pk, balance) do
    assert Account.balance(Chain.chain_state().accounts, pk) == balance
  end

  def spend(pk, sk, receiver, amount) do
    {:ok, tx} = Account.spend(pk, sk, receiver, amount, 10, Account.nonce(Chain.chain_state().accounts, pk) + 1)
    Pool.add_transaction(tx)
  end

  def spend_list(pk, sk, list) do
    spend_list(pk, sk, list, Account.nonce(Chain.chain_state().accounts, pk) +  1)
  end

  defp spend_list(_pk, _sk, [], _) do
    :ok
  end

  defp spend_list(pk, sk, [{receiver, amount} | rest], nonce) do
    {:ok, tx} = Account.spend(pk, sk, receiver, amount, 10, nonce)
    Pool.add_transaction(tx)
    spend_list(pk, sk, rest, nonce + 1)
  end

  def assert_transactions_mined() do
    Miner.mine_sync_block_to_chain
    assert Enum.empty?(Pool.get_and_empty_pool()) == true
  end

  def clean_blockchain() do
    Persistence.delete_all_blocks()
    Chain.clear_state()
    Pool.get_and_empty_pool()
    :ok
  end

end
