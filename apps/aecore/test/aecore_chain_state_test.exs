defmodule AecoreChainStateTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.ChainState, as: ChainState
  alias Aecore.Chain.Worker, as: Chain

  @tag :chain_state
  test "chain state" do
    next_block_height = Chain.top_block().header.height + 1
    chain_state =
      ChainState.calculate_and_validate_chain_state!([
        %SignedTx{data: %DataTx{type: SpendTx,
                                payload: %{to_acc: "a",
                                           value: 1,
                                           lock_time_block: 0},
                                from_acc: "b",
                                nonce: 2,
                                fee: 0},
                  signature: <<0>>},
        %SignedTx{data: %DataTx{type: SpendTx,
                                payload: %{to_acc: "a",
                                           value: 2,
                                           lock_time_block: 0},
                                from_acc: "c",
                                nonce: 2,
                                fee: 0},
                  signature: <<0>>}
      ],
        %{"a" => %{balance: 3, nonce: 100, locked: [%{amount: 1, block: next_block_height}]},
          "b" => %{balance: 5, nonce: 1, locked: [%{amount: 1, block: next_block_height + 1}]},
          "c" => %{balance: 4, nonce: 1, locked: [%{amount: 1, block: next_block_height}]}},
        1)

    assert %{"a" => %{balance: 6, nonce: 100,
                      locked: [%{amount: 1, block: next_block_height}]},
             "b" => %{balance: 4, nonce: 2,
                      locked: [%{amount: 1, block: next_block_height + 1}]},
             "c" => %{balance: 2, nonce: 2,
                      locked: [%{amount: 1, block: next_block_height}]}} == chain_state

    new_chain_state_locked_amounts =
      ChainState.update_chain_state_locked(chain_state, next_block_height)

    assert %{"a" => %{balance: 7, nonce: 100, locked: []},
             "b" => %{balance: 4, nonce: 2, locked: [%{amount: 1, block: next_block_height + 1}]},
             "c" => %{balance: 3, nonce: 2, locked: []}} == new_chain_state_locked_amounts
  end

end
