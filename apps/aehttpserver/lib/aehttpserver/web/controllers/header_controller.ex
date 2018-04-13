defmodule Aehttpserver.Web.HeaderController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Serialization
  alias Aeutil.HTTPUtil

  def top(conn, _params) do
    header = Serialization.serialize_value(Chain.top_block().header)
    json(conn, header)
  end

  def header_by_hash(conn, %{"hash" => hash}) do
    case Chain.get_header_by_base58_hash(hash) do
      {:ok, header} ->
        json(conn, Serialization.serialize_value(header))

      {:error, :invalid_hash} ->
        HTTPUtil.json_bad_request(conn, "Invalid hash")

      {:error, :header_not_found} ->
        HTTPUtil.json_not_found(conn, "Header not found")
    end
  end

  def header_by_height(conn, %{"height" => height}) do
    parsed_height = height |> Integer.parse() |> elem(0)

    with true <- parsed_height > 0,
         {:ok, header} <- Chain.get_header_by_height(parsed_height) do
      json(conn, Serialization.serialize_value(header))
    else
      _ ->
        HTTPUtil.json_not_found(conn, "Header not found")
    end
  end
end
