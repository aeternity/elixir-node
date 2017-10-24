defmodule Aehttpclient.Client do
  @moduledoc """
  Client used for making requests to a node.
  """

  @spec get_info(term()) :: {:ok, map()} | :error
  def get_info(uri) do
    case(HTTPoison.get(uri <> "/info")) do
      {:ok, %{body: body, status_code: 200}} ->
        response = Poison.decode!(body)
        {:ok, response}
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        :error
      {:error, %HTTPoison.Error{}} ->
        :error
    end
  end

  @doc """
  Send newest transactions to a peer
  """
  @spec broadcast_tx(String.t, map()) :: {:ok, map()} | {:error, term()}
  def broadcast_tx(uri, tx) do
    HTTPoison.post uri <> "/new_tx", tx,
        [{"Content-Type", "application/json"}]
  end
end
