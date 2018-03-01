defmodule AecoreChainStateTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Account
  alias Aecore.Chain.ChainState
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys.Worker, as: Keys

  @a1 :crypto.generate_key(:ecdh, :crypto.ec_curve(:secp256k1))
  @a2 :crypto.generate_key(:ecdh, :crypto.ec_curve(:secp256k1))
  @a3 :crypto.generate_key(:ecdh, :crypto.ec_curve(:secp256k1))

  @tag :chain_state
  test "chain state" do
    next_block_height = Chain.top_block().header.height + 1
    {{ap, as}, {bp, bs}, {cp, cs}} = {@a1, @a2, @a3}
    tx1 = %TxData{from_acc: bp, to_acc: ap, value: 1, nonce: 2, 
      fee: 0, lock_time_block: 0, data: %{}}
    {:ok, signed_tx1} = Keys.sign_txdata(tx1, bs)
    tx2 = %TxData{from_acc: cp, to_acc: ap, value: 2, nonce: 2, 
      fee: 0, lock_time_block: 0, data: %{}}
    {:ok, signed_tx2} = Keys.sign_txdata(tx2, cs)
    header = Header.create(0, <<0>>, <<0>>, <<0>>, 1, 0, Block.current_block_version())  
    chain_state =
      ChainState.calculate_and_validate_chain_state!([signed_tx1, signed_tx2],
        %{ap => %Account{balance: 3, nonce: 100, locked: [%{amount: 1, block: next_block_height}]},
          bp => %Account{balance: 5, nonce: 1, locked: [%{amount: 1, block: next_block_height + 1}]},
          cp => %Account{balance: 4, nonce: 1, locked: [%{amount: 1, block: next_block_height}]}}, header)
    assert %{ap => %Account{balance: 6, nonce: 100,
                             locked: [%{amount: 1, block: next_block_height}]},
             bp => %Account{balance: 4, nonce: 2,
                             locked: [%{amount: 1, block: next_block_height + 1}]},
             cp => %Account{balance: 2, nonce: 2,
               locked: [%{amount: 1, block: next_block_height}]}}
      == chain_state
    
    header_next = Header.create(next_block_height, <<0>>, <<0>>, <<0>>, 1, 0, Block.current_block_version())  
    new_chain_state_locked_amounts =
      ChainState.update_chain_state_locked(chain_state, header_next)
    assert %{ap => %Account{balance: 7, nonce: 100, locked: []},
             bp => %Account{balance: 4, nonce: 2, locked: [%{amount: 1, block: next_block_height + 1}]},
             cp => %Account{balance: 3, nonce: 2, locked: []}} 
      == new_chain_state_locked_amounts
  end

end
