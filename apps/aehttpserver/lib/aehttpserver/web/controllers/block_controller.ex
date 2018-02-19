defmodule Aehttpserver.Web.BlockController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Serialization
  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Block
  alias Aecore.Peers.Sync

  def show(conn, params) do
    block = Chain.get_block_by_hex_hash(params["hash"])
    case (block) do
      %Block{} ->
        block_hex_values = Serialization.block(block, :serialize)
        json(conn, block_hex_values)
      {:error, message} ->
        json(%{conn | status: 404}, %{error: message})
    end
  end

  def get_blocks(conn, params) do
    from_block_hash = case Map.get(params, "from_block") do
      nil ->
        Chain.top_block_hash()
      hash ->
        {_, hash_bin} = Base.decode16(hash)
        hash_bin
    end

    count = case Map.get(params, "count") do
      nil ->
        100
      count_string ->
        {number, _} = Integer.parse(count_string)
        number
    end

    blocks = Chain.get_blocks(from_block_hash, count)
    blocks_json = Enum.map(
      blocks,
      fn (block) ->
        hash = BlockValidation.block_header_hash(block.header)
        %{
          "hash" => Base.encode16(hash),
          "header" => Serialization.block(block, :serialize).header,
          "tx_count" => Enum.count(block.txs)
        }
      end
    )
    json conn, blocks_json
  end

  def get_raw_blocks(conn, params) do
    from_block_hash = case Map.get(params, "from_block") do
      nil ->
        Chain.top_block_hash()
      hash ->
        {_, hash_bin} = Base.decode16(hash)
        hash_bin
    end

    to_block_hash = case Map.get(params, "to_block") do
      nil ->
        BlockValidation.block_header_hash(Block.genesis_block().header)
      hash ->
        {_, hash_bin} = Base.decode16(hash)
        hash_bin
    end

    count = case Map.get(params, "count") do
      nil ->
        1000
      count_string ->
        {number, _} = Integer.parse(count_string)
        number
    end

    blocks = Chain.get_blocks(from_block_hash, to_block_hash, count)
    blocks_json = Enum.map(
      blocks,
      fn(block) ->
        Serialization.block(block, :serialize)
      end
    )

    json conn, blocks_json
  end

  def new_block(conn, _params) do
    block = Aeutil.Serialization.block(conn.body_params, :deserialize)
    block_hash = BlockValidation.block_header_hash(block.header)
    Sync.add_block_to_state(block_hash, block)
    Sync.add_valid_peer_blocks_to_chain(Sync.get_peer_blocks())
    json conn, %{ok: "new block received"}
  end
end
