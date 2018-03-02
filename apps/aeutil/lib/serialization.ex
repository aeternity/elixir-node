defmodule Aeutil.Serialization do
  @moduledoc """
  Utility module for serialization
  """

  alias __MODULE__
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.ContractProposalTxData
  alias Aecore.Structures.ContractCallTxData
  alias Aecore.Chain.ChainState
  alias Aeutil.Bits

  @type hash_types :: :chainstate | :header | :txs

  @spec block(Block.t(), :serialize | :deserialize) :: Block.t()
  def block(block, direction) do
    new_header = %{block.header |
      chain_state_hash: bech32_binary(block.header.chain_state_hash, :chainstate, direction),
      prev_hash: bech32_binary(block.header.prev_hash, :header, direction),
      txs_hash: bech32_binary(block.header.txs_hash, :txs, direction)}
    new_txs = Enum.map(block.txs, fn(tx) -> tx(tx, direction) end)
    Block.new(%{block | header: Header.new(new_header), txs: new_txs})
  end

  @spec tx(SignedTx.t(), :serialize | :deserialize) :: SignedTx.t()
  def tx(tx, direction) do
    new_tx_data =
      case tx.data do
        %SpendTx{} ->
          new_data = %{tx.data |
                       from_acc: hex_binary(tx.data.from_acc, direction),
                       to_acc: hex_binary(tx.data.to_acc, direction)}
          SpendTx.new(new_data)
        %ContractProposalTxData{} ->
          new_data = %{tx.data |
                       creator: hex_binary(tx.data.creator, direction)}
          ContractProposalTxData.new(new_data)
        %ContractCallTxData{} ->
          new_data = %{tx.data |
                       contract_proposal_tx_hash:
                        hex_binary(tx.data.contract_proposal_tx_hash, direction)}
          ContractCallTxData.new(new_data)
      end

      new_signature = base64_binary(tx.signature, direction)
      %SignedTx{data: SpendTx.new(new_tx_data), signature: new_signature}
  end

  @spec hex_binary(binary(), :serialize | :deserialize) :: String.t() | binary()
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
          :chainstate ->
            ChainState.bech32_encode(data)
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
