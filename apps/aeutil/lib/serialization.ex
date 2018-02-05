defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Structures.OracleRegistrationTxData
  alias Aecore.Structures.OracleResponseTxData

  def build_tx(tx) do
    cond do
      TxData.is_tx_data_tx(tx["data"]) ->
        SignedTx.new(%{tx | "data" => TxData.new(tx["data"])})
      OracleQueryTxData.is_oracle_query_tx(tx["data"]) ->
        SignedTx.new(%{tx | "data" => OracleQueryTxData.new(tx["data"])})
      OracleRegistrationTxData.is_oracle_registration_tx(tx["data"]) ->
        SignedTx.new(%{tx | "data" => OracleRegistrationTxData.new(tx["data"])})
      OracleResponseTxData.is_oracle_response_tx(tx["data"]) ->
        SignedTx.new(%{tx | "data" => OracleResponseTxData.new(tx["data"])})
    end
  end

  @spec block(Block.t(), :serialize | :deserialize) :: Block.t()
  def block(block, direction) do
    new_header = %{block.header |
      chain_state_hash: hex_binary(block.header.chain_state_hash, direction),
      prev_hash: hex_binary(block.header.prev_hash, direction),
      txs_hash: hex_binary(block.header.txs_hash, direction)}
    new_txs =
      Enum.map(block.txs, fn(tx) ->
          if(direction == :deserialize) do
            tx |> build_tx() |> tx(direction)
          else
            tx(tx, direction)
          end
        end)
    Block.new(%{block | header: new_header, txs: new_txs})
  end

  @spec tx(SignedTx.t(), :serialize | :deserialize) :: SignedTx.t()
  def tx(tx, direction) do
    new_data =
      case tx.data do
        %TxData{} ->
          %{tx.data | from_acc: hex_binary(tx.data.from_acc, direction),
                      to_acc: hex_binary(tx.data.to_acc, direction)}
        %OracleRegistrationTxData{} ->
          %{tx.data | operator: hex_binary(tx.data.operator, direction)}
        %OracleResponseTxData{} ->
          %{tx.data | operator: hex_binary(tx.data.operator, direction)}
        %OracleQueryTxData{} ->
          %{tx.data | sender: hex_binary(tx.data.sender, direction),
                      oracle_hash: hex_binary(tx.data.oracle_hash, direction)}
      end
    new_signature = hex_binary(tx.signature, direction)
    %SignedTx{data: new_data, signature: new_signature}
  end

  @spec hex_binary(binary(), :serialize | :deserialize) :: binary()
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

  def merkle_proof(proof, acc) when is_tuple(proof) do
    proof
    |> Tuple.to_list()
    |> merkle_proof(acc)
  end

  def merkle_proof([], acc), do: acc

  def merkle_proof([head | tail], acc) do
    if is_tuple(head) do
      merkle_proof(Tuple.to_list(head), acc)
    else
      acc = [hex_binary(head, :serialize)| acc]
      merkle_proof(tail, acc)
    end
  end
end
