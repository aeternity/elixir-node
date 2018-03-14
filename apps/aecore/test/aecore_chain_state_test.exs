defmodule AecoreChainStateTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.ChainState
  alias Aecore.Structures.Account
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Wallet.Worker, as: Wallet

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

    {:ok, signed_tx1} = Account.spend(wallet.b_pub_key, wallet.b_priv_key, wallet.a_pub_key, 1, 1, 2)
    {:ok, signed_tx2} = Account.spend(wallet.c_pub_key, wallet.c_priv_key, wallet.a_pub_key, 2, 1, 2)

    chain_state =
      ChainState.calculate_and_validate_chain_state!(
        [signed_tx1, signed_tx2],
        %{:accounts => %{wallet.a_pub_key => %Account{balance: 3,
                                                      nonce: 100},
                         wallet.b_pub_key => %Account{balance: 5,
                                                      nonce: 1},
                         wallet.c_pub_key => %Account{balance: 4,
                                                      nonce: 1}}},
        1)

    assert %{:accounts => %{wallet.a_pub_key => %Account{balance: 6,
                                                         nonce: 100},
                            wallet.b_pub_key => %Account{balance: 3,
                                                         nonce: 2},
                            wallet.c_pub_key => %Account{balance: 1,
                                                         nonce: 2}}} == chain_state

  end

end
