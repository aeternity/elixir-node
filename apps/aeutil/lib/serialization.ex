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
    alias Aecore.SigningPrototype.Contract
    alias Aecore.Chain.ChainState, as: Chain
    alias Aeutil.Bits

    @type transaction_types :: TxData.t() |
    ContractProposalTx.t() |
    ContractSignTx.t()

    @type hash_types :: :chainstate | :header | :txs | :signing_tx

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
        chain_state_hash: bech32_binary(header.chain_state_hash, :chainstate, direction),
        prev_hash: bech32_binary(header.prev_hash, :header, direction),
        txs_hash: bech32_binary(header.txs_hash, :txs, direction)}
    end

    @spec tx(SignedTx.t() | map(), :serialize | :deserialize) :: SignedTx.t()
    def tx(tx, direction) do
      {new_data, new_signature} =
        case direction do
          :deserialize ->
            built_tx_data = build_tx(tx["data"])
            data = serialize_tx_data(built_tx_data, direction)
            signature = base64_binary(tx["signature"], direction)
            {data, signature}
          :serialize ->
            data = serialize_tx_data(tx.data, direction)
            signature = base64_binary(tx.signature, direction)
            {data, signature}
        end
      %SignedTx{data: new_data, signature: new_signature}
     end

    @spec build_tx(map()) :: transaction_types()
    def build_tx(tx) do
      cond do
        SignedTx.is_spend_tx(tx) ->
          TxData.new(tx)
        SignedTx.is_contract_proposal_tx(tx) ->
          ContractProposalTx.new(tx)
        SignedTx.is_contract_sign_tx(tx) ->
          ContractSignTx.new(tx)
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
          %{tx_data | contract_hash: bech32_binary(tx_data.contract_hash, :signing_tx, direction),
            participants: Enum.map(tx_data.participants, fn tx -> hex_binary(tx, direction) end),
            from_acc: hex_binary(tx_data.from_acc, direction)}
        %ContractSignTx{} ->
          %{tx_data | signature: hex_binary(tx_data.signature, direction),
            from_acc: hex_binary(tx_data.from_acc, direction),
            contract_hash: bech32_binary(tx_data.contract_hash, :signing_tx, direction)}
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

    @spec bech32_binary(binary() | String.t, Serialization.hash_types(),
      :serialize | :deserialize) :: String.t() | binary()
    def bech32_binary(data, hash_type, direction) do
      case direction do
        :serialize ->
          case hash_type do
            :header ->
              Header.bech32_encode(data)
            :txs ->
              SignedTx.bech32_encode_root(data)
            :signing_tx ->
              Contract.bech32_encode(data)
            :chainstate ->
              Chain.bech32_encode(data)
          end
        :deserialize ->
          Bits.bech32_decode(data)
      end
      end

    @spec base64_binary(binary(), :serialize | :deserialize) :: String.t() | binary()
    def base64_binary(data, direction) do
      if data != nil do
        case(direction) do
          :serialize ->
            Base.encode64(data)
          :deserialize ->
            Base.decode64!(data)
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
