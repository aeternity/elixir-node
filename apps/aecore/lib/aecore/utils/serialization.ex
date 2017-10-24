defmodule Aecore.Utils.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.SignedTx

  @spec serialize_block(%Block{}) :: %Block{}
  def serialize_block(block) do
    new_header = %{block.header |
      chain_state_hash: Base.encode16(block.header.chain_state_hash),
      prev_hash: Base.encode16(block.header.prev_hash),
      txs_hash: Base.encode16(block.header.txs_hash)}
    new_txs = for tx <- block.txs do
      from_acc = if(tx.data.from_acc != nil) do
          Base.encode16(tx.data_from_acc)
        else
          nil
        end
      new_data = %{tx.data |
        from_acc: from_acc,
        to_acc: Base.encode16(tx.data.to_acc)}
      new_signature = if(tx.signature != nil) do
          Base.encode16(tx.signature)
        else
          nil
        end
      %SignedTx{data: new_data, signature: new_signature}
    end
    %{block | header: new_header, txs: new_txs}
  end
end
