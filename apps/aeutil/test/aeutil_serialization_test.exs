defmodule AeutilSerializationTest do
  use ExUnit.Case

  alias Aeutil.Serialization
  alias Aewallet.Encoding
  alias Aecore.Wallet.Worker, as: Wallet

  @tag :serialization
  test "serialize a block" do
    block = get_block()
    serialized_block = Serialization.block(block, :serialize)
    assert check_header_values(serialized_block)
    assert check_transactions(serialized_block)
    assert Serialization.block(serialized_block, :deserialize) == block
  end

  def check_header_values(block) do
    [_head | values] = Map.values(block.header)

    for value <- values do
      if is_binary(value) do
        case SegwitAddr.decode(value) do
          {:ok, _} ->
            true

          {:error, _} ->
            false
        end
      else
        true
      end
    end
    |> Enum.all?()
  end

  def check_transactions(block) do
    for tx <- block.txs do
      %{data: %{to_acc: to_acc}} = tx
      match?({:ok, _}, Encoding.decode(to_acc))
    end
    |> Enum.all?()
  end

  def get_block() do
    %Aecore.Structures.Block{
      header: %Aecore.Structures.Header{
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
        %Aecore.Structures.SignedTx{
          data: %Aecore.Structures.SpendTx{
            from_acc: nil,
            nonce: 743_183_534_114,
            to_acc: Wallet.get_public_key(),
            value: 100
          },
          signature: nil
        }
      ]
    }
  end
end
