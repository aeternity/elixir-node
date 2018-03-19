defmodule AeutilSerializationTest do
  use ExUnit.Case

  alias Aeutil.Serialization
  alias Aecore.Structures.DataTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aewallet.Encoding
  alias Aecore.Wallet.Worker, as: Wallet

  @tag :serialization
  test "serialize a block" do
    block = get_block()

    serialized_block = Serialization.block(block, :serialize)

    assert serialized_block == get_block_map()
    assert Serialization.block(serialized_block, :deserialize) == block
  end

  def get_block() do
    receiver =
      <<2, 121, 111, 28, 192, 67, 96, 59, 129, 233, 58, 160, 23, 170, 149, 224, 16, 95, 203, 138,
        175, 20, 173, 236, 11, 119, 247, 239, 229, 214, 249, 62, 214>>

    sender =
      <<2, 121, 111, 28, 192, 67, 96, 59, 129, 233, 58, 160, 23, 170, 149, 224, 16, 95, 203, 138,
        175, 20, 173, 236, 11, 119, 247, 239, 229, 214, 249, 62, 213>>

    %Block{
      header: %Header{
        chain_state_hash:
          <<30, 218, 194, 119, 38, 40, 34, 174, 222, 84, 181, 202, 247, 196, 94, 64, 9, 109, 222,
            28, 113, 175, 206, 113, 23, 161, 56, 109, 50, 163, 62, 34>>,
        difficulty_target: 11,
        height: 105,
        nonce: 707,
        prev_hash:
          <<0, 122, 160, 14, 73, 61, 172, 124, 241, 233, 182, 91, 53, 238, 233, 208, 138, 26, 59,
            211, 87, 245, 149, 71, 169, 84, 121, 95, 179, 150, 8, 203>>,
        timestamp: 1_508_834_903_252,
        txs_hash:
          <<1, 101, 93, 209, 124, 22, 197, 172, 222, 246, 210, 28, 228, 244, 155, 248, 3, 179,
            250, 105, 208, 85, 217, 215, 244, 150, 87, 214, 225, 71, 160, 240>>,
        version: 1
      },
      txs: [
        %SignedTx{
          data: %DataTx{
            type: SpendTx,
            payload: %SpendTx{
              receiver: receiver,
              amount: 100,
              lock_time_block: [%{amount: 5, block: 10}, %{amount: 6, block: 10}]
            },
            sender: sender,
            nonce: 743_183_534_114,
            fee: 40
          },
          signature: <<1, 2, 3>>
        }
      ]
    }
  end

  def get_block_map() do
    %{
      "header" => %{
        "chain_state_hash" => "cs1qrmdvyaex9q32ahj5kh9003z7gqykmhsuwxhuuugh5yux6v4r8c3qr0a5xn",
        "difficulty_target" => 11,
        "height" => 105,
        "nonce" => 707,
        "pow_evidence" => nil,
        "prev_hash" => "bl1qqpa2qrjf8kk8eu0fkedntmhf6z9p5w7n2l6e23af23u4lvukpr9sx0k0su",
        "timestamp" => 1_508_834_903_252,
        "txs_hash" => "tr1qq9j4m5tuzmz6ehhk6gwwfaymlqpm87nf6p2an4l5jetadc285rcqc8xlyf",
        "version" => 1
      },
      "txs" => [
        %{
          "data" => %{
            "type" => "Elixir.Aecore.Structures.SpendTx",
            "payload" => %{
              "receiver" => "ae1qqfuk78xqgdsrhq0f82sp0254uqg9lju24u22mmqtwlm7lewklyldv5nwq9g",
              "amount" => 100,
              "lock_time_block" => [
                %{"amount" => 5, "block" => 10},
                %{"amount" => 6, "block" => 10}
              ]
            },
            "sender" => "ae1qqfuk78xqgdsrhq0f82sp0254uqg9lju24u22mmqtwlm7lewklyld2gud9el",
            "fee" => 40,
            "nonce" => 743_183_534_114
          },
          "signature" => "AQID"
        }
      ]
    }
  end
end
