defmodule Aecore.Utils.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.TxData

  @spec block(%Block{}, :serialize | :deserialize) :: %Block{}
  def block(block, direction) do
    new_header =
      %{block.header |
        chain_state_hash: hex_binary(block.header.chain_state_hash, direction),
        prev_hash: hex_binary(block.header.prev_hash, direction),
        txs_hash: hex_binary(block.header.txs_hash, direction)}
    new_txs = for tx <- block.txs do
      from_acc = if(tx.data.from_acc != nil) do
        hex_binary(tx.data_from_acc, direction)
      else
        nil
      end
      new_data = %{tx.data |
                   from_acc: from_acc,
                   to_acc: hex_binary(tx.data.to_acc, direction)}

      new_signature = if(tx.signature != nil) do
        hex_binary(tx.signature, direction)
      else
        nil
      end
      %SignedTx{data: TxData.new(new_data), signature: new_signature}
    end
    Block.new(%{block | header: Header.new(new_header), txs: new_txs})
  end

  def hex_binary(data, direction) do
    case(direction) do
      :serialize ->
        Base.encode16(data)
      :deserialize ->
        Base.decode16!(data)
    end
  end
end
