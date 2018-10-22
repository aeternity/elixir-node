defmodule AecoreChainstateTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Account.Account
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Account.AccountStateTree
  alias Aecore.Chain.Chainstate

  setup do
    Code.require_file("test_utils.ex", "./test")
    TestUtils.clean_blockchain()

    on_exit(fn ->
      TestUtils.clean_blockchain()
    end)
  end

  setup do
    %{public: a_pub_key} = :enacl.sign_keypair()
    %{public: b_pub_key, secret: b_priv_key} = :enacl.sign_keypair()
    %{public: c_pub_key, secret: c_priv_key} = :enacl.sign_keypair()

    [
      a_pub_key: a_pub_key,
      b_pub_key: b_pub_key,
      b_priv_key: b_priv_key,
      c_pub_key: c_pub_key,
      c_priv_key: c_priv_key
    ]
  end

  @tag :chain_state
  test "chain state", wallet do
    init_accounts_state = Chain.chain_state().accounts

    signed_tx1 =
      Account.spend(wallet.b_pub_key, wallet.b_priv_key, wallet.a_pub_key, 1, 1, 2, <<"payload">>)

    signed_tx2 =
      Account.spend(wallet.c_pub_key, wallet.c_priv_key, wallet.a_pub_key, 2, 1, 2, <<"payload">>)

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
      apply_txs_on_state([signed_tx1, signed_tx2], %{:accounts => accounts_chainstate}, 1)

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

  def apply_txs_on_state(txs, chainstate, block_height) do
    Enum.reduce_while(txs, chainstate, fn tx, chainstate ->
      case Chainstate.apply_transaction_on_state(chainstate, block_height, tx) do
        {:ok, new_state} -> {:cont, new_state}
        {:error, _reason} -> {:halt, :error}
      end
    end)
  end
end
