defmodule AecoreChainstateTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Structures.Account
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Structures.AccountStateTree
  alias Aecore.Structures.Chainstate

  setup do
    on_exit(fn ->
      Persistence.delete_all_blocks()
      Chain.clear_state()
      :ok
    end)
  end

  setup wallet do
    [
      a_pub_key: Wallet.get_public_key(),
      b_pub_key: Wallet.get_public_key("M/0"),
      b_priv_key: Wallet.get_private_key("m/0"),
      c_pub_key: Wallet.get_public_key("M/1"),
      c_priv_key: Wallet.get_private_key("m/1")
    ]
  end

  @tag :chain_state
  test "chain state", wallet do
    init_accounts_state = Chain.chain_state().accounts

    {:ok, signed_tx1} =
      Account.spend(wallet.b_pub_key, wallet.b_priv_key, wallet.a_pub_key, 1, 1, 2)

    {:ok, signed_tx2} =
      Account.spend(wallet.c_pub_key, wallet.c_priv_key, wallet.a_pub_key, 2, 1, 2)

    init_accounts = %{
      wallet.a_pub_key => %Account{balance: 3, nonce: 100},
      wallet.b_pub_key => %Account{balance: 5, nonce: 1},
      wallet.c_pub_key => %Account{balance: 4, nonce: 1}
    }

    accounts_chainstate =
      Enum.reduce(init_accounts, init_accounts_state, fn {k, v}, acc ->
        AccountStateTree.put(acc, k, v)
      end)

    chain_state =
      apply_txs_on_state!([signed_tx1, signed_tx2], %{:accounts => accounts_chainstate}, 1)

    assert {6, 100} ==
             {
               Account.balance(chain_state.accounts, wallet.a_pub_key),
               Account.nonce(chain_state.accounts, wallet.a_pub_key)
             }

    assert {3, 2} ==
             {
               Account.balance(chain_state.accounts, wallet.b_pub_key),
               Account.nonce(chain_state.accounts, wallet.b_pub_key)
             }

    assert {1, 2} ==
             {
               Account.balance(chain_state.accounts, wallet.c_pub_key),
               Account.nonce(chain_state.accounts, wallet.c_pub_key)
             }
  end

  def apply_txs_on_state!(txs, chainstate, block_height) do
    txs
    |> Enum.reduce(chainstate, fn tx, chainstate ->
      Chainstate.apply_transaction_on_state!(tx, chainstate, block_height)
    end)
  end
end
