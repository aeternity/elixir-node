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
        json conn, block_hex_values
      {:error, message} ->
        json %{conn | status: 404}, %{error: message}
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

  def new_block(conn, _params) do
    ## Becouse we 'conn.body_params' contains decoded json as map with
    ## keys as strings instead of atoms we are doing this workaround
    map = Poison.decode!(Poison.encode!(conn.body_params), [keys: :atoms])
    block = Aeutil.Serialization.block(map, :deserialize)
    block_hash = BlockValidation.block_header_hash(block.header)
    Sync.add_block_to_state(block_hash, block)
    Sync.add_valid_peer_blocks_to_chain()
    json conn, %{ok: "new block received"}
  end
end
