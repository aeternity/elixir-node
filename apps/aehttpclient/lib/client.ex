defmodule Aehttpclient.Client do
  @moduledoc """
  Client used for making requests to a node.
  """

  alias Aecore.Structures.Block

  @spec get_info(term()) :: {:ok, map()} | :error
  def get_info(uri) do
    get(uri <> "/info", :info)
  end

  def get_block({uri, hash}) do
    get(uri <> "/block/#{hash}", :block)
  end

  def get(uri, identifier) do
    case(HTTPoison.get(uri)) do
      {:ok, %{body: body, status_code: 200}} ->
        case(identifier) do
          :block ->
            response = Poison.decode!(body, as: %Block{}, keys: :atoms!)
            {:ok, response}
          :info ->
            response = Poison.decode!(body, keys: :atoms!)
            {:ok, response}
        end
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        :error
      {:error, %HTTPoison.Error{}} ->
        :error
    end
  end

  @doc """
  Send newest transactions to a peer
  """
  @spec send_tx(String.t, map()) :: {:ok, map()} | {:error, term()}
  def send_tx(uri, tx) do
    HTTPoison.post uri <> "/new_tx", Poison.encode!(tx),
        [{"Content-Type", "application/json"}]
  end
end
