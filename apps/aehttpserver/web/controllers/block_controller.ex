defmodule Aehttpserver.BlockController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Serialization
  alias Aecore.Structures.Block

  def show(conn, params) do
    block = Chain.get_block_by_hash(params["hash"])
    case (block) do
      %Block{} ->
        block_hex_values = Serialization.serialize_block(block)
        json conn, block_hex_values
      {:error, message} ->
        json conn, %{error: message}
    end
  end
end
