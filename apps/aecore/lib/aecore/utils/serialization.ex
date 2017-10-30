defmodule Aecore.Utils.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.SignedTx

  @spec block(%Block{}, :serialize | :deserialize) :: %Block{}
  def block(block, direction) do
    new_header = %{block.header |
      chain_state_hash: hex_binary(block.header.chain_state_hash, direction),
      prev_hash: hex_binary(block.header.prev_hash, direction),
      txs_hash: hex_binary(block.header.txs_hash, direction)}
    new_txs = Enum.map(block.txs, fn(tx) -> tx(tx,direction) end)
    %{block | header: new_header, txs: new_txs}
  end

  @spec tx(map(), :serialize | :deserialize) :: map() | {:error, term()}
  def tx(tx, direction) do
    new_data = %{tx.data |
      from_acc: hex_binary(tx.data.from_acc, direction),
      to_acc: hex_binary(tx.data.to_acc, direction)}
    new_signature = hex_binary(tx.signature, direction)
    %SignedTx{data: new_data, signature: new_signature}
  end

  def hex_binary(data, direction) do
    if(data != nil) do
      case(direction) do
        :serialize ->
          Base.encode16(data)
        :deserialize ->
          Base.decode16!(data)
      end
    else
      nil
    end
  end
end
