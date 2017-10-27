defmodule Aehttpclient.Client do
  @moduledoc """
  Client used for making requests to a node.
  """

  alias Aecore.Structures.Block
  alias Aecore.Peers.Worker, as: Peers

  @spec get_info(term()) :: {:ok, map()} | :error
  def get_info(uri) do
    get(uri <> "/info", :info)
  end

  @spec get_block({term(), term()}) :: {:ok, %Block{}} | :error
  def get_block({uri, hash}) do
    get(uri <> "/block/#{hash}", :block)
  end

  @spec get_peers(term()) :: {:ok, list()}
  def get_peers(uri) do
    get(uri <> "/peers", :peers)
  end

  @spec get_and_add_peers(term()) :: :ok
  def get_and_add_peers(uri) do
    {:ok, peers} = get_peers(uri)
    Enum.each(peers, fn{peer, _} -> Peers.add_peer(peer) end)
  end

  def get_account_balance({uri,acc}) do
    get(uri <> "/balance/#{acc}", :balance)
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
          :peers ->
            standard_response(body)
          :balance ->
            standard_response(body)
        end
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        :error
      {:error, %HTTPoison.Error{}} ->
        :error
    end
  end

  def standard_response(body) do
    response = Poison.decode!(body)
    {:ok,response}
  end
end
