defmodule Aehttpclient.Client do

  def ping_self do
    response = HTTPoison.get!("localhost:4000/ping")
    json_response = Poison.decode!(response.body)
  end

end
