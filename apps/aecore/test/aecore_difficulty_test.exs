defmodule DifficultyTest do
  use ExUnit.Case

  doctest Aecore.Chain.Difficulty

  alias Aecore.Chain.Difficulty, as: Difficulty
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header

  @tag :difficulty
  test "difficulty calculation genesis block only" do
    blocks = [
      Block.genesis_block()
    ]

    timestamp = 1_607_275_094_308
    assert 553_713_663 == Difficulty.calculate_next_difficulty(timestamp, blocks)
  end

  @tag :difficulty
  test "difficulty calculation" do
    blocks = [
      %Block{
        header: %Header{
          target: 553_713_663,
          height: 1,
          nonce: 0,
          prev_hash: <<1, 24, 45>>,
          time: 130_000,
          txs_hash: "\f{\f",
          version: 1
        },
        txs: []
      },
      %Block{
        header: %Header{
          target: 553_713_663,
          height: 1,
          nonce: 0,
          prev_hash: <<1, 24, 45>>,
          time: 20_000,
          txs_hash: "\f{\f",
          version: 1
        },
        txs: []
      },
      %Block{
        header: %Header{
          target: 553_713_663,
          height: 0,
          nonce: 0,
          prev_hash:
            <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0>>,
          time: 10_000,
          txs_hash:
            <<0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
              0, 0, 0, 0>>,
          version: 1
        },
        txs: []
      }
    ]

    timestamp = 140_000
    assert 553_713_663 == Difficulty.calculate_next_difficulty(timestamp, blocks)
  end
end
