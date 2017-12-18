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
  alias Aecore.Chain.Worker, as: Chain

  test "block state" do
    block = get_block()
    lock_time_block = Enum.at(block.txs, 0).data.lock_time_block
    latest_block = Chain.top_block()

    assert %{"a" => %{balance: -9, nonce: 102,
                      locked: [%{amount: 10, block: lock_time_block}]},
             "b" => %{nonce: 1, balance: -11,
                      locked: [%{amount: 4, block: lock_time_block},
                               %{amount: 5, block: lock_time_block}]},
             "c" => %{nonce: 1, balance: -5,
                      locked: [%{amount: 2, block: lock_time_block}]}} ==
      ChainState.calculate_block_state(block.txs, latest_block.header.height)
  end

  test "chain state" do
    next_block_height = Chain.top_block().header.height + 1
    chain_state =
      ChainState.calculate_chain_state(%{"a" => %{balance: 3, nonce: 100,
                                                  locked: [%{amount: 1, block: next_block_height}]},
                                         "b" => %{balance: 5, nonce: 1,
                                                  locked: [%{amount: 1, block: next_block_height + 1}]},
                                         "c" => %{balance: 4, nonce: 1,
                                                  locked: [%{amount: 1, block: next_block_height}]}},
        %{"a" => %{balance:  3, nonce: 0, locked: []},
          "b" => %{balance: -1, nonce: 0, locked: []},
          "c" => %{balance: -2, nonce: 0, locked: []}})
    assert %{"a" => %{balance: 6, nonce: 100,
                      locked: [%{amount: 1, block: next_block_height}]},
             "b" => %{balance: 4, nonce: 1,
                      locked: [%{amount: 1, block: next_block_height + 1}]},
             "c" => %{balance: 2, nonce: 1,
                      locked: [%{amount: 1, block: next_block_height}]}} == chain_state

    new_chain_state_locked_amounts =
      ChainState.update_chain_state_locked(chain_state, next_block_height)
    assert %{"a" => %{balance: 7, nonce: 100, locked: []},
             "b" => %{balance: 4, nonce: 1, locked: [%{amount: 1, block: next_block_height + 1}]},
             "c" => %{balance: 3, nonce: 1, locked: []}} == new_chain_state_locked_amounts
  end

  defp get_block() do
    %Block{header: %Header{height: 1, prev_hash: <<1, 24, 45>>,
           txs_hash: <<12, 123, 12>>, difficulty_target: 0, nonce: 0,
           timestamp: System.system_time(:milliseconds), version: 1}, txs: [
             %SignedTx{data: %TxData{from_acc: "a", to_acc: "b",
              value: 5, nonce: 101, fee: 1,
              lock_time_block: Chain.top_block().header.height +
                Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1},
              signature: <<0>>},

             %SignedTx{data: %TxData{from_acc: "a", to_acc: "c",
              value: 2, nonce: 102, fee: 1,
              lock_time_block: Chain.top_block().header.height +
                Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1},
              signature: <<0>>},

             %SignedTx{data: %TxData{from_acc: "c", to_acc: "b",
              value: 4, nonce: 1, fee: 1,
              lock_time_block: Chain.top_block().header.height +
                Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1},
              signature: <<0>>},

             %SignedTx{data: %TxData{from_acc: "b", to_acc: "a",
              value: 10, nonce: 1, fee: 1,
              lock_time_block: Chain.top_block().header.height +
                Application.get_env(:aecore, :tx_data)[:lock_time_coinbase] + 1},
              signature: <<0>>}]}
  end

end
