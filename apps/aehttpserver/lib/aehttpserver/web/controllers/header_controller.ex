defmodule Aehttpserver.Web.HeaderController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Worker, as: Chain
  alias Aeutil.Serialization

  def top(conn, _params) do
    header = Serialization.serialize_value(Chain.top_block().header)
    json(conn, header)
  end

  def header_by_hash(conn, %{"hash" => hash}) do
    case Chain.get_header_by_base58_hash(hash) do
      {:error, :invalid_hash} ->
        json(put_status(conn, 400), "Invalid hash")

      {:error, :header_not_found} ->
        json(put_status(conn, 404), "Header not found")

      header ->
        json(conn, Serialization.serialize_value(header))
    end
  end

  def header_by_height(conn, %{"height" => height}) do
    parsed_height = height |> Integer.parse() |> elem(0)

    if(parsed_height < 0) do
      json(put_status(conn, 400), "Header not found")
    else
      case Chain.get_header_by_height(parsed_height) do
        {:error, :header_not_found} ->
          json(put_status(conn, 400), "Header not found")

        header ->
          json(conn, Serialization.serialize_value(header))
      end
    end
  end
end
