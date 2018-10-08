defmodule Aehttpserver.Web.BlockController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Serialization
  alias Aeutil.HTTPUtil
  alias Aecore.Chain.{Block, Header, Genesis}
  alias Aeutil.Serialization

  def block_by_height(conn, %{"height" => height}) do
    parsed_height = height |> Integer.parse() |> elem(0)

    if parsed_height < 0 do
      HTTPUtil.json_not_found(conn, "Block not found")
    else
      case Chain.get_block_by_height(parsed_height) do
        {:ok, block} ->
          json(conn, Serialization.serialize_value(block))

        {:error, :chain_too_short} ->
          HTTPUtil.json_not_found(conn, "Chain too short")
      end
    end
  end

  def block_by_hash(conn, %{"hash" => hash}) do
    case Chain.get_block_by_base58_hash(hash) do
      {:ok, block} ->
        json(conn, Block.encode_to_map(block))

      {:error, :block_not_found} ->
        HTTPUtil.json_not_found(conn, "Block not found")

      {:error, :invalid_hash} ->
        HTTPUtil.json_bad_request(conn, "Invalid hash")
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
        hash = Header.hash(block.header)

        %{
          "hash" => Header.base58c_encode(hash),
          "header" => Map.delete(Block.encode_to_map(block), "transactions"),
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
          Header.hash(Genesis.block().header)

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
        Block.encode_to_map(block)
      end)

    json(conn, blocks_json)
  end
end
