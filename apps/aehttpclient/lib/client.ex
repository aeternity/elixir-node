defmodule Aehttpclient.Client do

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
end
