defmodule Aehttpclient.Client do

  def ping_uri(uri) do
    case(HTTPoison.get(uri <> "/ping")) do
      {:ok, %{status_code: status_code}} when status_code == 200 ->
        :ok
      true ->
        :error
    end
  end
end
