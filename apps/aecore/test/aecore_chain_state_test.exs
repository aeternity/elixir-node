defmodule AecoreChainStateTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Structures.TxData, as: TxData
  alias Aecore.Structures.SignedTx, as: SignedTx
  alias Aecore.Chain.ChainState, as: ChainState
  alias Aecore.Chain.Worker, as: Chain

  setup wallet do
    [
      a_pub_key: <<4, 16, 237, 169, 120, 141, 247, 208, 230, 42, 148, 48, 197, 186, 62, 216, 15,
      184, 80, 37, 35, 79, 67, 63, 189, 173, 148, 248, 80, 60, 255, 45, 133, 151,
      149, 66, 34, 171, 100, 101, 30, 58, 0, 161, 123, 164, 189, 225, 245, 79, 38,
      16, 171, 117, 149, 203, 140, 97, 116, 253, 130, 248, 224, 179, 164>>,

      b_priv_key: <<22, 132, 116, 219, 203, 89, 110, 175, 27, 101, 191, 56, 132, 79, 126, 251,
      153, 30, 54, 41, 229, 165, 125, 198, 109, 67, 186, 132, 60, 112, 15, 64>>,

      b_pub_key: <<4, 157, 132, 19, 126, 48, 144, 239, 87, 216, 235, 145, 163, 52, 135, 69, 35,
      34, 244, 252, 209, 12, 218, 213, 147, 105, 130, 205, 8, 178, 81, 196, 101,
      184, 63, 33, 166, 223, 239, 48, 98, 204, 214, 97, 16, 225, 28, 26, 43, 173,
      201, 205, 248, 1, 79, 238, 23, 152, 199, 243, 176, 5, 112, 111, 193>>,

      c_priv_key: <<130, 201, 184, 98, 98, 73, 194, 7, 46, 130, 10, 145, 109, 254, 227, 69, 11,
      223, 33, 194, 225, 68, 198, 72, 179, 85, 190, 6, 32, 74, 124, 137>>,

      c_pub_key: <<4, 81, 181, 128, 248, 136, 64, 17, 157, 125, 226, 13, 190, 84, 85, 50, 51,
      170, 28, 90, 251, 112, 135, 33, 138, 142, 204, 13, 245, 133, 1, 21, 233, 54,
      144, 177, 17, 178, 41, 187, 201, 163, 157, 141, 169, 64, 48, 26, 128, 197,
      96, 92, 24, 27, 186, 47, 205, 140, 115, 11, 210, 247, 172, 74, 165>>
    ]
  end

  @tag :chain_state
  test "chain state", wallet do
    next_block_height = Chain.top_block().header.height + 1

    tx_1 = %TxData{from_acc: wallet.b_pub_key, to_acc: wallet.a_pub_key,
                   value: 1, nonce: 2, fee: 0, lock_time_block: 0}
    {:ok, signed_tx1} = SignedTx.sign_tx(tx_1, wallet.b_priv_key)

    tx_2 = %TxData{from_acc: wallet.c_pub_key, to_acc: wallet.a_pub_key,
              value: 2, nonce: 2, fee: 0, lock_time_block: 0}
    {:ok, signed_tx2} = SignedTx.sign_tx(tx_2, wallet.c_priv_key)

    chain_state =
      ChainState.calculate_and_validate_chain_state!([signed_tx1, signed_tx2],
        %{wallet.a_pub_key => %{balance: 3, nonce: 100, locked: [%{amount: 1, block: next_block_height}]},
          wallet.b_pub_key => %{balance: 5, nonce: 1, locked: [%{amount: 1, block: next_block_height + 1}]},
          wallet.c_pub_key => %{balance: 4, nonce: 1, locked: [%{amount: 1, block: next_block_height}]}}, 1)

    assert %{wallet.a_pub_key => %{balance: 6, nonce: 100,
                      locked: [%{amount: 1, block: next_block_height}]},
             wallet.b_pub_key => %{balance: 4, nonce: 2,
                      locked: [%{amount: 1, block: next_block_height + 1}]},
             wallet.c_pub_key => %{balance: 2, nonce: 2,
                      locked: [%{amount: 1, block: next_block_height}]}} == chain_state

    new_chain_state_locked_amounts =
      ChainState.update_chain_state_locked(chain_state, next_block_height)

    assert %{wallet.a_pub_key => %{balance: 7, nonce: 100, locked: []},
             wallet.b_pub_key => %{balance: 4, nonce: 2, locked: [%{amount: 1, block: next_block_height + 1}]},
             wallet.c_pub_key => %{balance: 3, nonce: 2, locked: []}} == new_chain_state_locked_amounts
  end

end
