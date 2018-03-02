defmodule AecoreChainStateTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Account
  alias Aecore.Chain.ChainState, as: ChainState
  alias Aecore.Chain.Worker, as: Chain

  @tag :chain_state
  test "chain state" do
    next_block_height = Chain.top_block().header.height + 1
    a = String.duplicate("a", 65)
    b = String.duplicate("b", 65)
    c = String.duplicate("c", 65)
    chain_state =
      ChainState.calculate_and_validate_chain_state!([
        %SignedTx{data: %SpendTx{from_acc: b, to_acc: a,
              value: 1, nonce: 2, fee: 0, lock_time_block: 0}, signature: <<0>>},
        %SignedTx{data: %SpendTx{from_acc: c, to_acc: a,
              value: 2, nonce: 2, fee: 0, lock_time_block: 0}, signature: <<0>>}],
        %{a => %Account{balance: 3, nonce: 100, locked: [%{amount: 1, block: next_block_height}]},
          b => %Account{balance: 5, nonce: 1, locked: [%{amount: 1, block: next_block_height + 1}]},
          c => %Account{balance: 4, nonce: 1, locked: [%{amount: 1, block: next_block_height}]}}, 1)
    assert %{a => %Account{balance: 6, nonce: 100,
                             locked: [%{amount: 1, block: next_block_height}]},
             b => %Account{balance: 4, nonce: 2,
                             locked: [%{amount: 1, block: next_block_height + 1}]},
             c => %Account{balance: 2, nonce: 2,
               locked: [%{amount: 1, block: next_block_height}]}}
      == chain_state

    new_chain_state_locked_amounts =
      ChainState.update_chain_state_locked(chain_state, next_block_height)
    assert %{a => %Account{balance: 7, nonce: 100, locked: []},
             b => %Account{balance: 4, nonce: 2, locked: [%{amount: 1, block: next_block_height + 1}]},
             c => %Account{balance: 3, nonce: 2, locked: []}} 
      == new_chain_state_locked_amounts
  end

end
