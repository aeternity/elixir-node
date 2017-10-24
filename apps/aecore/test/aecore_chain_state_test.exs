defmodule AecoreChainStateTest do
  @moduledoc """
  Unit test for the chain module
  """

  use ExUnit.Case

  alias Aecore.Structures.Block, as: Block
  alias Aecore.Structures.Header, as: Header
  alias Aecore.Structures.TxData, as: TxData
  alias Aecore.Structures.SignedTx, as: SignedTx
  alias Aecore.Chain.ChainState, as: ChainState

  test "block state" do
    block = get_block()

    assert %{"a" => %{balance:  3, nonce: 2},
             "b" => %{balance: -1, nonce: 1},
             "c" => %{balance: -2, nonce: 1}} ==
      ChainState.calculate_block_state(block.txs)
  end

  test "chain state" do
    chain_state =
      ChainState.calculate_chain_state(%{"a" => %{balance: 3, nonce: 1},
                                         "b" => %{balance: 5, nonce: 1},
                                         "c" => %{balance: 4, nonce: 1}},
        %{"a" => %{balance:  3, nonce: 0},
          "b" => %{balance: -1, nonce: 0},
          "c" => %{balance: -2, nonce: 0}})
    assert %{"a" => %{balance: 6, nonce: 1},
             "b" => %{balance: 4, nonce: 1},
             "c" => %{balance: 2, nonce: 1}} == chain_state
  end

  defp get_block() do
    %Block{header: %Header{height: 1, prev_hash: <<1, 24, 45>>,
           txs_hash: <<12, 123, 12>>, difficulty_target: 0, nonce: 0,
           timestamp: System.system_time(:milliseconds), version: 1}, txs: [
             %SignedTx{data: %TxData{from_acc: "a", to_acc: "b",
              value: 5}, signature: <<0>>},
             %SignedTx{data: %TxData{from_acc: "a", to_acc: "c",
              value: 2}, signature: <<0>>},
             %SignedTx{data: %TxData{from_acc: "c", to_acc: "b",
              value: 4}, signature: <<0>>},
             %SignedTx{data: %TxData{from_acc: "b", to_acc: "a",
              value: 10}, signature: <<0>>}]}
  end

end
