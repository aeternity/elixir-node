defmodule AeutilSerializationTest do
  use ExUnit.Case

  alias Aeutil.Serialization
  alias Aecore.Tx.DataTx
  alias Aecore.Tx.SignedTx
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Chain.Identifier

  @tag :serialization
  test "serialize a block" do
    block = get_block()

    serialized_block = Serialization.block(block, :serialize)
    assert serialized_block == get_block_map()
    assert Serialization.block(serialized_block, :deserialize) == block
  end

  def get_block do
    receiver =
      <<2, 121, 111, 28, 192, 67, 96, 59, 129, 233, 58, 160, 23, 170, 149, 224, 16, 95, 203, 138,
        175, 20, 173, 236, 11, 119, 247, 239, 229, 214, 249, 62, 214>>

    sender =
      <<2, 121, 111, 28, 192, 67, 96, 59, 129, 233, 58, 160, 23, 170, 149, 224, 16, 95, 203, 138,
        175, 20, 173, 236, 11, 119, 247, 239, 229, 214, 249, 62, 213>>

    %Block{
      header: %Header{
        root_hash:
          <<30, 218, 194, 119, 38, 40, 34, 174, 222, 84, 181, 202, 247, 196, 94, 64, 9, 109, 222,
            28, 113, 175, 206, 113, 23, 161, 56, 109, 50, 163, 62, 34>>,
        target: 11,
        height: 105,
        nonce: 707,
        prev_hash:
          <<0, 122, 160, 14, 73, 61, 172, 124, 241, 233, 182, 91, 53, 238, 233, 208, 138, 26, 59,
            211, 87, 245, 149, 71, 169, 84, 121, 95, 179, 150, 8, 203>>,
        time: 1_508_834_903_252,
        txs_hash:
          <<1, 101, 93, 209, 124, 22, 197, 172, 222, 246, 210, 28, 228, 244, 155, 248, 3, 179,
            250, 105, 208, 85, 217, 215, 244, 150, 87, 214, 225, 71, 160, 240>>,
        version: 1,
        miner:
          <<2, 121, 111, 28, 192, 67, 96, 59, 129, 233, 58, 160, 23, 170, 149, 224, 16, 95, 203,
            138, 175, 20, 173, 236, 11, 119, 247, 239, 229, 214, 249, 62, 214>>
      },
      txs: [
        %SignedTx{
          data: %DataTx{
            type: SpendTx,
            payload: %SpendTx{
              receiver: %Identifier{value: receiver, type: :account},
              amount: 100,
              version: 1,
              payload: <<"some payload">>
            },
            senders: [%Identifier{type: :account, value: sender}],
            nonce: 743_183_534_114,
            fee: 40,
            ttl: 0
          },
          signatures: [<<1, 2, 3>>]
        }
      ]
    }
  end

  def get_block_map do
    %{
      "transactions" => [
        %{
          "data" => %{
            "fee" => 40,
            "sender" => "ak$5oyDtV2JbBpZxTCS5JacVfPQHKjxCdoRaxRS93tPHcwvcxHFFZ",
            "nonce" => 743_183_534_114,
            "payload" => %{
              "receiver" => "ak$5oyDtV2JbBpZxTCS5JacVfPQHKjxCdoRaxRS93tPHcwvqTtyvz",
              "amount" => 100,
              "version" => 1,
              "payload" => "some payload"
            },
            "type" => "Elixir.Aecore.Account.Tx.SpendTx",
            "ttl" => 0
          },
          "signature" => "sg$3DUz7ncyT"
        }
      ],
      "height" => 105,
      "nonce" => 707,
      "pow" => nil,
      "prev_hash" => "bh$1DEfLSYrZUviQKtzfJvRv1pAJuwn62nk9q9cBUaPjPubMxcBk",
      "state_hash" => "bs$Eb8yjCFDCzG8oJJKQC3GTHpj3gwuqdjsddSiHrgvvKRbMsWFy",
      "target" => 11,
      "time" => 1_508_834_903_252,
      "txs_hash" => "bx$cfAVxohyXoDtv7euNiQXxCJH6ULcZjw5gUzaDLi1rwa43ee6",
      "miner" => "ak$5oyDtV2JbBpZxTCS5JacVfPQHKjxCdoRaxRS93tPHcwvqTtyvz",
      "version" => 1
    }
  end
end
