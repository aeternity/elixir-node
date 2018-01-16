defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.MultisigTx
  alias Aecore.Structures.ChannelTxData

  @spec block(%Block{}, :serialize | :deserialize) :: %Block{}
  def block(block, direction) do
    new_header = %{block.header |
      chain_state_hash: hex_binary(block.header.chain_state_hash, direction),
      prev_hash: hex_binary(block.header.prev_hash, direction),
      txs_hash: hex_binary(block.header.txs_hash, direction)}
    new_txs = Enum.map(block.txs, fn(tx) -> tx(tx, direction) end)
    Block.new(%{block | header: Header.new(new_header), txs: new_txs})
  end

  @spec tx(map(), :serialize | :deserialize) :: map() | {:error, term()}
  def tx(tx, direction) do
    cond do
      SignedTx.is_signed_tx?(tx) ->
        new_data = %{tx.data |
                     from_acc: hex_binary(tx.data.from_acc, direction),
                     to_acc: hex_binary(tx.data.to_acc, direction)}
        new_signature = hex_binary(tx.signature, direction)
        %SignedTx{data: TxData.new(new_data), signature: new_signature}
      MultisigTx.is_multisig_tx?(tx)->
        if(!Map.has_key?(tx, "data")) do
          new_data =
            %ChannelTxData{lock_amounts:
                           serialize_keys(tx.data.lock_amounts, direction),
                           fee: tx.data.fee}
          %MultisigTx{data: new_data,
                      signatures: serialize_map(tx.signatures, direction)}
        else
          new_data =
            ChannelTxData.new(%{"lock_amounts" =>
                                serialize_keys(tx["data"]["lock_amounts"],
                                               direction),
                                "fee" => tx["data"]["fee"]})
          MultisigTx.new(%{"data" => new_data,
                           "signatures" =>
                           serialize_map(tx["signatures"], direction)})
        end
    end
  end

  def serialize_map(map, direction) do
    Enum.reduce(map, %{}, fn({key, value}, acc) ->
        if(is_atom(key)) do
          Map.put(acc, hex_binary(to_string(key), direction), hex_binary(value, direction))
        else
          Map.put(acc, hex_binary(key, direction), hex_binary(value, direction))
        end
      end)
  end

  def serialize_keys(map, direction) do
    Enum.reduce(map, %{}, fn({key, value}, acc) ->
        if(is_atom(key)) do
          Map.put(acc, hex_binary(to_string(key), direction), value)
        else
          Map.put(acc, hex_binary(key, direction), value)
        end
      end)
  end

  def hex_binary(data, direction) do
    if data != nil do
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
