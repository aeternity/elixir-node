defmodule Aehttpserver.Web.BlockController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Serialization
  alias Aecore.Chain.BlockValidation
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Peers.Sync
  alias Aeutil.Serialization

  def block_by_height(conn, %{"height" => height}) do
    parsed_height = height |> Integer.parse() |> elem(0)

    if(parsed_height < 0) do
      json(put_status(conn, 404), "Block not found")
    else
      case Chain.get_block_by_height(parsed_height) do
        {:error, :chain_too_short} ->
          json(put_status(conn, 404), "Chain too short")

        header ->
          json(conn, Serialization.serialize_value(header))
      end
    end
  end

  def block_by_hash(conn, %{"hash" => hash}) do
    case Chain.get_block_by_base58_hash(hash) do
      {:error, :block_not_found} ->
        json(put_status(conn, 404), "Block not found")

      {:error, :invalid_hash} ->
        json(put_status(conn, 400), "Invalid hash")

      block ->
        json(conn, Serialization.block(block, :serialize))
    end
  end

  def get_blocks(conn, params) do
    from_block_hash =
      case Map.get(params, "from_block") do
        nil ->
          Chain.top_block_hash()

        hash ->
          Header.base58c_decode(hash)
      end

    count =
      case Map.get(params, "count") do
        nil ->
          100

        count_string ->
          {number, _} = Integer.parse(count_string)
          number
      end

    blocks = Chain.get_blocks(from_block_hash, count)

    blocks_json =
      Enum.map(blocks, fn block ->
        hash = BlockValidation.block_header_hash(block.header)

        %{
          "hash" => Header.base58c_encode(hash),
          "header" => Serialization.block(block, :serialize).header,
          "tx_count" => Enum.count(block.txs)
        }
      end)

    json(conn, blocks_json)
  end

  def get_raw_blocks(conn, params) do
    from_block_hash =
      case Map.get(params, "from_block") do
        nil ->
          Chain.top_block_hash()

        hash ->
          Header.base58c_decode(hash)
      end

    to_block_hash =
      case Map.get(params, "to_block") do
        nil ->
          BlockValidation.block_header_hash(Block.genesis_block().header)

        hash ->
          Header.base58c_decode(hash)
      end

    count =
      case Map.get(params, "count") do
        nil ->
          1000

        count_string ->
          {number, _} = Integer.parse(count_string)
          number
      end

    blocks = Chain.get_blocks(from_block_hash, to_block_hash, count)

    blocks_json =
      Enum.map(blocks, fn block ->
        Serialization.block(block, :serialize)
      end)

    json(conn, blocks_json)
  end

  def post_block(conn, _params) do
    block = Serialization.block(conn.body_params, :deserialize)

    try do
      BlockValidation.single_validate_block!(block)
      block_hash = BlockValidation.block_header_hash(block.header)
      Sync.add_block_to_state(block_hash, block)
      Sync.add_valid_peer_blocks_to_chain(Sync.get_peer_blocks())
      json(conn, "successful operation")
    catch
      {:error, _message} ->
        json(put_status(conn, 200), "Block or header validation error")
    end
  end
end
