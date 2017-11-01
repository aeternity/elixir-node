defmodule Aehttpserver.BlockController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Serialization
  alias Aecore.Structures.Block

  def show(conn, params) do
    block = Chain.get_block_by_hex_hash(params["hash"])
    case (block) do
      %Block{} ->
        block_hex_values = Serialization.block(block, :serialize)
        json conn, block_hex_values
      {:error, message} ->
        json conn, %{error: message}
    end
  end

  def new_block(conn, params) do
    ## Becouse we 'conn.body_params' contains decoded json as map with
    ## keys as strings instead of atoms we are doing this workaround
    map = Poison.decode!(Poison.encode!(conn.body_params), [keys: :atoms])

    block = Aecore.Utils.Serialization.block(map, :deserialize)

    Aecore.Chain.Worker.add_block(block)
    json conn, %{ok: "new block received"}
  end
end
