defmodule AeutilSerializationTest do
  use ExUnit.Case

  alias Aeutil.Serialization
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.SpendTx

  @tag :serialization
  test "serialize a block" do
    block = get_block()

    serialized_block = Serialization.block(block, :serialize)

    #assert check_header_values(serialized_block)
    #assert check_transactions(serialized_block)

    assert serialized_block == get_block_map()
    assert Serialization.block(serialized_block, :deserialize) == block
  end

  def check_header_values(block) do
    [_head | values] = Map.values(block["header"])
    for value <- values do
      if is_binary(value) do
        case(SegwitAddr.decode(value)) do
          {:ok, _} ->
            true
          {:error, _} ->
            false
        end
      else
        true
      end
    end |> Enum.all?()
  end

  def check_transactions(block) do
    for tx <- block["txs"] do
      %{data: %{payload: %{to_acc: to_acc}, from_acc: from_acc}, signature: signature} = tx
      for value <- [from_acc, to_acc, signature] do
        if is_binary(value) do
          case(Base.decode16(value)) do
            {:ok, _} ->
              true
            :error ->
              false
          end
        else
          true
        end
      end |> Enum.all?()
    end |> Enum.all?()
  end

  def get_block() do

    to_acc = <<4, 121, 111, 28, 192, 67, 96, 59, 129, 233, 58, 160, 23, 170, 149, 224, 16, 95, 203, 138, 175, 20, 173, 236, 11, 119, 247, 239, 229, 214, 249, 62, 214, 1, 164, 99, 95, 167, 141, 75, 205, 154, 199, 247, 141, 240, 152, 235, 1, 17, 44, 69, 181, 36, 123, 180, 170, 125, 93, 238, 185, 212, 11, 212, 44>>

    %Aecore.Structures.Block{header: %Aecore.Structures.Header{chain_state_hash: <<30,
    218, 194, 119, 38, 40, 34, 174, 222, 84, 181, 202, 247, 196, 94, 64, 9, 109,
    222, 28, 113, 175, 206, 113, 23, 161, 56, 109, 50, 163, 62, 34>>,
    difficulty_target: 11, height: 105, nonce: 707,
    prev_hash: <<0, 122, 160, 14, 73, 61, 172, 124, 241, 233, 182, 91, 53, 238,
    233, 208, 138, 26, 59, 211, 87, 245, 149, 71, 169, 84, 121, 95, 179, 150, 8,
    203>>, timestamp: 1_508_834_903_252,
    txs_hash: <<1, 101, 93, 209, 124, 22, 197, 172, 222, 246, 210, 28, 228, 244,
    155, 248, 3, 179, 250, 105, 208, 85, 217, 215, 244, 150, 87, 214, 225, 71,
    160, 240>>, version: 1},
    txs: [%SignedTx{data: %DataTx{type: SpendTx,
                                  payload: %SpendTx{to_acc: Aewallet.KeyPair.compress(to_acc),
                                                    value: 100,
                                                    lock_time_block: [%{amount: 5,
                                                                        block: 10},
                                                                      %{amount: 6,
                                                                        block: 10}]},
                                  from_acc: <<1, 2, 3>>,
                                  nonce: 743_183_534_114,
                                  fee: 40},
                    signature: <<1, 2, 3>>}]}
  end

  def get_block_map() do
    to_acc =  "04796F1CC043603B81E93AA017AA95E0105FCB8AAF14ADEC0B77F7EFE5D6F93ED601A4635FA78D4BCD9AC7F78DF098EB01112C45B5247BB4AA7D5DEEB9D40BD42C"

    %{"header" => %{"chain_state_hash" => "1EDAC277262822AEDE54B5CAF7C45E40096DDE1C71AFCE7117A1386D32A33E22",
                    "difficulty_target" => 11,
                    "height" => 105,
                    "nonce" => 707,
                    "pow_evidence" => nil,
                    "prev_hash" => "007AA00E493DAC7CF1E9B65B35EEE9D08A1A3BD357F59547A954795FB39608CB",
                    "timestamp" => 1_508_834_903_252,
                    "txs_hash" => "01655DD17C16C5ACDEF6D21CE4F49BF803B3FA69D055D9D7F49657D6E147A0F0",
                    "version" => 1},
      "txs" => [%{"data" => %{"type" => "Elixir.Aecore.Structures.SpendTx",
                              "payload" => %{"to_acc" => to_acc,
                                             "value" => 100,
                                             "lock_time_block" => [%{"amount" => 5,
                                                                     "block" => 10},
                                                                   %{"amount" => 6,
                                                                     "block" => 10}]
                                            },
                              "from_acc" => "010203",
                              "fee" => 40,
                              "nonce" => 743_183_534_114},
                  "signature" => "010203"}]
    }
  end
end
