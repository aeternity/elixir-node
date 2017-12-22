defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Structures.OracleRegistrationTxData
  alias Aecore.Structures.OracleResponseTxData

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
    new_data =
      cond do
        match?(%OracleQueryTxData{}, tx.data) ->
          %{tx.data | sender: hex_binary(tx.data.sender, direction),
                      oracle_hash: hex_binary(tx.data.oracle_hash, direction)}
        match?(%OracleRegistrationTxData{}, tx.data) ->
          %{tx.data | operator: hex_binary(tx.data.operator, direction)}
        match?(%OracleResponseTxData{}, tx.data) ->
          %{tx.data | operator: hex_binary(tx.data.operator, direction)}
        match?(%TxData{}, tx.data) ->
          %{tx.data | from_acc: hex_binary(tx.data.from_acc, direction),
                      to_acc: hex_binary(tx.data.to_acc, direction)}
      end
    new_signature = hex_binary(tx.signature, direction)
    %SignedTx{data: new_data, signature: new_signature}
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
