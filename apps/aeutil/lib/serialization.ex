defmodule Aeutil.Serialization do
    @moduledoc """
  Utility module for serialization
    """

    alias Aecore.Structures.Block
    alias Aecore.Structures.Header
    alias Aecore.Structures.TxData
    alias Aecore.Structures.SignedTx
    alias Aecore.Structures.ContractProposalTx
    alias Aecore.Structures.ContractSignTx

    @type transaction_types :: TxData.t() |
    ContractProposalTx.t() |
    ContractSignTx.t()

    @spec block(Block.t(), :serialize | :deserialize) :: Block.t()
    def block(block, direction) do
      {new_header, new_txs} =
        case direction do
          :deserialize ->
            built_header = Header.new(block["header"])
            header = header(built_header, direction)
            txs = Enum.map(block["txs"], fn(tx) ->
              tx(tx, direction)
            end)
            {header, txs}
          :serialize ->
            header = header(block.header, direction)
            txs = Enum.map(block.txs, fn(tx) ->
              tx(tx, direction)
            end)
            {header, txs}
        end
      Block.new(header: new_header, txs: new_txs)
    end

    @spec header(Header.t(), :serialize | :deserialize) :: Header.t()
    def header(header, direction) do
      %{header |
        chain_state_hash: hex_binary(header.chain_state_hash, direction),
        prev_hash: hex_binary(header.prev_hash, direction),
        txs_hash: hex_binary(header.txs_hash, direction)}
    end

    @spec tx(SignedTx.t(), :serialize | :deserialize) :: SignedTx.t()
    def tx(tx, direction) do
      {new_data, new_signature} =
        case direction do
          :deserialize ->
            built_tx_data = build_tx(tx).data
            data = serialize_tx_data(built_tx_data, direction)
            signature = hex_binary(tx["signature"], direction)
            {data, signature}
          :serialize ->
            data = serialize_tx_data(tx.data, direction)
            signature = hex_binary(tx.signature, direction)
            {data, signature}
        end
      %SignedTx{data: new_data, signature: new_signature}
    end

    @spec build_tx(map()) :: transaction_types()
    def build_tx(tx) do
      cond do
        SignedTx.is_spend_tx(tx["data"]) ->
          SignedTx.new(%{tx | "data" => TxData.new(tx["data"])})
        SignedTx.is_contract_proposal_tx(tx["data"]) ->
          SignedTx.new(%{tx | "data" => ContractProposalTx.new(tx["data"])})
        SignedTx.is_contract_sign_tx(tx["data"]) ->
          SignedTx.new(%{tx | "data" => ContractSignTx.new(tx["data"])})
      end
    end

    @spec serialize_tx_data(transaction_types(),
      :serialize | :deserialize) :: transaction_types()
    def serialize_tx_data(tx_data, direction) do
      case tx_data do
        %TxData{} ->
          %{tx_data | from_acc: hex_binary(tx_data.from_acc, direction),
            to_acc: hex_binary(tx_data.to_acc, direction)}
        %ContractProposalTx{} ->
          %{tx_data | contract_hash: hex_binary(tx_data.contract_hash, direction),
            participants: Enum.map(tx_data.participants, fn x -> hex_binary(x, :serialize) end),
            from_acc: hex_binary(tx_data.from_acc, direction)}
        %ContractSignTx{} ->
          %{tx_data | signature: hex_binary(tx_data.signature, direction),
            from_acc: hex_binary(tx_data.from_acc, direction),
            contract_hash: hex_binary(tx_data.contract_hash, direction)}
      end
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

    @spec pack_binary(term()) :: map()
    def pack_binary(term) do
      case term do
        %Block{} ->
          Map.from_struct(%{term | header: Map.from_struct(term.header)})
        %SignedTx{} ->
          Map.from_struct(%{term | data: Map.from_struct(term.data)})
        %{__struct__: _} ->
          Map.from_struct(term)
        _ ->
          term
      end
      |> Msgpax.pack!(iodata: false)
    end
end
