defmodule AecoreChainStateTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Chain.ChainState
  alias Aecore.Structures.Account
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Wallet.Worker, as: Wallet

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
    next_block_height = Chain.top_block().header.height + 1

    {:ok, signed_tx1} =
      Account.spend(wallet.b_pub_key, wallet.b_priv_key, wallet.a_pub_key, 1, 1, 2)

    {:ok, signed_tx2} =
      Account.spend(wallet.c_pub_key, wallet.c_priv_key, wallet.a_pub_key, 2, 1, 2)

    chain_state =
      apply_txs_on_state!(
        [signed_tx1, signed_tx2],
        %{
          :accounts => %{
            wallet.a_pub_key => %Account{
              balance: 3,
              nonce: 100,
              locked: [%{amount: 1, block: next_block_height}]
            },
            wallet.b_pub_key => %Account{
              balance: 5,
              nonce: 1,
              locked: [%{amount: 1, block: next_block_height + 1}]
            },
            wallet.c_pub_key => %Account{
              balance: 4,
              nonce: 1,
              locked: [%{amount: 1, block: next_block_height}]
            }
          }
        },
        1
      )

    assert %{
             :accounts => %{
               wallet.a_pub_key => %Account{
                 balance: 6,
                 nonce: 100,
                 locked: [%{amount: 1, block: next_block_height}]
               },
               wallet.b_pub_key => %Account{
                 balance: 3,
                 nonce: 2,
                 locked: [%{amount: 1, block: next_block_height + 1}]
               },
               wallet.c_pub_key => %Account{
                 balance: 1,
                 nonce: 2,
                 locked: [%{amount: 1, block: next_block_height}]
               }
             }
           } == chain_state

    new_chain_state_locked_amounts =
      ChainState.update_chain_state_locked(chain_state, next_block_height)

    assert %{
             :accounts => %{
               wallet.a_pub_key => %Account{balance: 7, nonce: 100, locked: []},
               wallet.b_pub_key => %Account{
                 balance: 3,
                 nonce: 2,
                 locked: [%{amount: 1, block: next_block_height + 1}]
               },
               wallet.c_pub_key => %Account{balance: 2, nonce: 2, locked: []}
             }
           } == new_chain_state_locked_amounts
  end

  def apply_txs_on_state!(txs, chainstate, block_height) do
    txs
    |> Enum.reduce(chainstate, fn tx, chainstate ->
      ChainState.apply_transaction_on_state!(tx, chainstate, block_height)
    end)
  end
end
