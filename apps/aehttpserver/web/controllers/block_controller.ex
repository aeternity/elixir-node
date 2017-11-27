defmodule Aehttpserver.BlockController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Serialization
  alias Aecore.Utils.Blockchain.BlockValidation
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
    latest_block_hash = case Map.get(params, "from_block") do
      nil ->
        latest_block = Chain.latest_block()
        BlockValidation.block_header_hash(latest_block.header)
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

    IO.inspect(latest_block_hash)
    IO.inspect(count)

    blocks = Chain.get_blocks(latest_block_hash, count)
    blocks_json = Enum.map(blocks, fn (block) -> Serialization.block(block, :serialize)   end)
    json conn, blocks_json
  end

  def new_block(conn, _params) do
    ## Becouse we 'conn.body_params' contains decoded json as map with
    ## keys as strings instead of atoms we are doing this workaround
    map = Poison.decode!(Poison.encode!(conn.body_params), [keys: :atoms])
    block = Aecore.Utils.Serialization.block(map, :deserialize)
    block_hash = BlockValidation.block_header_hash(block.header)
    Sync.add_block_to_state(block_hash, block)
    Sync.add_valid_peer_blocks_to_chain()
    json conn, %{ok: "new block received"}
  end
end
