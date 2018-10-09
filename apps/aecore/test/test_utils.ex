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
  alias Aecore.Keys

  def get_accounts_chainstate do
    Chain.chain_state().accounts
  end

  def assert_balance(pk, balance) do
    assert Account.balance(Chain.chain_state().accounts, pk) == balance
  end

  def miner_spend(receiver, amount) do
    {pubkey, privkey} = Keys.keypair(:sign)
    spend(pubkey, privkey, receiver, amount)
  end

  def spend(pk, sk, receiver, amount) do
    Account.spend(
      pk,
      sk,
      receiver,
      amount,
      10,
      Account.nonce(Chain.chain_state().accounts, pk) + 1,
      ""
    )
  end

  def spend_list(pk, sk, list) do
    spend_list(pk, sk, list, Account.nonce(Chain.chain_state().accounts, pk) + 1)
  end

  defp spend_list(_pk, _sk, [], _) do
    :ok
  end

  defp spend_list(pk, sk, [{receiver, amount} | rest], nonce) do
    Account.spend(pk, sk, receiver, amount, 10, nonce, <<>>)
    spend_list(pk, sk, rest, nonce + 1)
  end

  def assert_transactions_mined do
    :ok = Miner.mine_sync_block_to_chain()
    assert Enum.empty?(Pool.get_and_empty_pool()) == true
  end

  defp restart_supervisor(supervisor) do
    :ok = Supervisor.terminate_child(Aecore, supervisor)
    {:ok, _} = Supervisor.restart_child(Aecore, supervisor)
  end

  def clean_blockchain do
    :ok = Persistence.delete_all()
    restart_supervisor(Aecore.Channel.Worker.Supervisor)
    restart_supervisor(Aecore.Chain.Worker.Supervisor)
    restart_supervisor(Aecore.Tx.Pool.Worker.Supervisor)
    :ok
  end
end
