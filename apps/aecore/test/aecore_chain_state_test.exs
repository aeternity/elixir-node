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

  @tag :chain_state
  test "chain state" do
    next_block_height = Chain.top_block().header.height + 1
    {{ap, as}, {bp, bs}, {cp, cs}} = get_accounts()
    tx1 = %TxData{from_acc: bp, to_acc: ap, value: 1, nonce: 2, 
      fee: 0, lock_time_block: 0, data: %{}}
    {:ok, sig_tx1} = Keys.sign(tx1, bs)
    signed_tx1 = %SignedTx{data: tx1, signature: sig_tx1}
    tx2 = %TxData{from_acc: cp, to_acc: ap, value: 2, nonce: 2, 
      fee: 0, lock_time_block: 0, data: %{}}
    {:ok, sig_tx2} = Keys.sign(tx2, cs)
    signed_tx2 = %SignedTx{data: tx2, signature: sig_tx2}
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

  defp get_accounts do
    account1 = {
        <<4, 113, 73, 130, 150, 200, 126, 80, 231, 110, 11, 224, 246, 121, 247, 201,
          166, 210, 85, 162, 163, 45, 147, 212, 141, 68, 28, 179, 91, 161, 139, 237,
          168, 61, 115, 74, 188, 140, 143, 160, 232, 230, 187, 220, 17, 24, 249, 202,
          222, 19, 20, 136, 175, 241, 203, 82, 23, 76, 218, 9, 72, 42, 11, 123, 127>>,
        <<198, 218, 48, 178, 127, 24, 201, 115, 3, 29, 188, 220, 222, 189, 132, 139,
          168, 1, 64, 134, 103, 38, 151, 213, 195, 5, 219, 138, 29, 137, 119, 229>>
      }
    account2 = {
        <<4, 44, 202, 225, 249, 173, 82, 71, 56, 32, 113, 206, 123, 220, 201, 169, 40,
          91, 56, 206, 54, 114, 162, 48, 226, 255, 87, 3, 113, 161, 45, 231, 163, 50,
          116, 30, 204, 109, 69, 255, 54, 78, 238, 249, 34, 139, 9, 35, 99, 246, 181,
          238, 165, 123, 67, 66, 217, 176, 227, 237, 64, 84, 65, 73, 141>>,
        <<44, 81, 132, 144, 204, 94, 98, 172, 51, 110, 175, 30, 195, 124, 217, 172,
          242, 240, 60, 102, 96, 91, 195, 138, 253, 247, 130, 188, 62, 229, 62, 37>>
      }
    account3 = {
        <<4, 11, 38, 199, 95, 205, 49, 85, 168, 55, 88, 105, 244, 159, 57, 125, 71,
          128, 119, 87, 224, 135, 195, 98, 218, 32, 225, 96, 254, 88, 55, 219, 164,
          148, 30, 203, 57, 24, 121, 208, 160, 116, 231, 94, 229, 135, 225, 47, 16,
          162, 250, 63, 103, 111, 249, 66, 67, 21, 133, 54, 152, 61, 119, 51, 188>>,
      <<19, 239, 205, 35, 76, 49, 9, 230, 59, 169, 195, 217, 222, 135, 204, 201, 160,
 126, 253, 20, 230, 122, 184, 193, 131, 53, 157, 50, 117, 29, 195, 47>>
      }
    {account1, account2, account3}
  end
        
end
