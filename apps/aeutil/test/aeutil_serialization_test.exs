defmodule AeutilSerializationTest do

  use ExUnit.Case

  alias Aeutil.Serialization
  alias Aeutil.Bits

  @tag :serialization
  test "serialize a block" do
    block = get_block()
    serialized_block = Serialization.block(block, :serialize)
    assert check_header_values(serialized_block)
    assert check_transactions(serialized_block)
    block_map = get_block_map()
    assert Serialization.block(block_map, :deserialize) == block
  end

  def check_header_values(block) do
    [_head | values] = Map.values(block.header)
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
    for tx <- block.txs do
      %{data: %{from_acc: from_acc, to_acc: to_acc}, signature: signature} = tx
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
    %Aecore.Structures.Block{
      header: %Aecore.Structures.Header{
        chain_state_hash: <<194, 149, 104, 199, 218, 174, 149, 130, 255, 177, 230,
        47, 179, 137, 241, 104, 127, 121, 29, 77, 194, 62, 109, 10, 227, 8, 34,
        147, 173, 69, 0, 139>>,
        difficulty_target: 1,
        height: 1,
        nonce: 100,
        pow_evidence: [396336, 613835, 623264, 643439, 663633, 31623636, 31626565,
                       31626637, 31653763, 31653833, 32333339, 32343965, 32666364, 33303064,
                       33303165, 33373336, 33376466, 33626562, 34336337, 34353866, 34373463,
                       34373830, 34386163, 34626436, 34636265, 34653262, 35316363, 35323832,
                       35393435, 35393436, 35393563, 35626634, 35656164, 36323365, 36333337,
                       36343231, 36393361, 36396432, 36616666, 37343638, 37623335, 37623936],
        prev_hash: <<8, 29, 133, 32, 174, 126, 31, 174, 40, 134, 218, 6, 148, 142,
        143, 29, 30, 113, 20, 78, 116, 101, 124, 116, 166, 209, 141, 79, 89, 40,
        80, 113>>,
        timestamp: 1519382030538,
        txs_hash: <<187, 45, 76, 248, 118, 32, 183, 125, 6, 117, 210, 91, 190, 55,
        34, 29, 180, 222, 31, 247, 239, 233, 79, 182, 46, 41, 228, 36, 148, 161,
        168, 161>>,
        version: 1
},
      txs: [
        %Aecore.Structures.SignedTx{
          data: %Aecore.Structures.TxData{
            fee: 0,
            from_acc: nil,
            lock_time_block: 11,
            nonce: 0,
            to_acc:  <<4, 89, 53, 128, 121, 117, 1, 174, 193, 199, 63, 36, 12, 123, 218, 29, 87,
            199, 161, 174, 235, 161, 192, 148, 222, 157, 135, 152, 185, 11, 41, 244, 224,
            57, 22, 195, 71, 159, 178, 248, 18, 49, 180, 136, 31, 127, 119, 254, 22, 36,
            164, 173, 185, 138, 50, 126, 89, 81, 12, 91, 169, 185, 211, 52, 219>>,
            value: 100
},
          signature: nil
}
      ]
    }
  end

  def get_block_map() do
    %{
      "header" => %{
    "chain_state_hash" => "cs1qc22k3376462c9la3uchm8z03dplhj82dcglx6zhrpq3f8t29qz9sx0dzud",
    "difficulty_target" => 1,
    "height" => 1,
    "nonce" => 100,
    "pow_evidence" => [396336, 613835, 623264, 643439, 663633, 31623636,
                       31626565, 31626637, 31653763, 31653833, 32333339, 32343965, 32666364,
                       33303064, 33303165, 33373336, 33376466, 33626562, 34336337, 34353866,
                       34373463, 34373830, 34386163, 34626436, 34636265, 34653262, 35316363,
                       35323832, 35393435, 35393436, 35393563, 35626634, 35656164, 36323365,
                       36333337, 36343231, 36393361, 36396432, 36616666, 37343638, 37623335,
                       37623936],
    "prev_hash" => "bl1qpqwc2g9w0c06u2yxmgrffr50r508z9zww3jhca9x6xx57kfg2pcsrhq9dp",
    "timestamp" => 1519382030538,
    "txs_hash" => "tr1qhvk5e7rkyzmh6pn46fdmudezrk6du8lhal55ld3w98jzf99p4zsskjf0a4",
    "version" => 1
  },
      "txs" => [
        %{
          "data" => %{
        "fee" => 0,
        "from_acc" => nil,
        "lock_time_block" => 11,
        "nonce" => 0,
        "to_acc" => "04593580797501AEC1C73F240C7BDA1D57C7A1AEEBA1C094DE9D8798B90B29F4E03916C3479FB2F81231B4881F7F77FE1624A4ADB98A327E59510C5BA9B9D334DB",
        "value" => 100
      },
          "signature" => nil
        }
      ]
    }
  end
  end
