defmodule Aehttpclient.Client do
  @moduledoc """
  Client used for making requests to a node.
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.TxData
  alias Aecore.Peers.Worker, as: Peers

  @spec get_info(term()) :: {:ok, map()} | :error
  def get_info(uri) do
    get(uri <> "/info", :info)
  end

  @spec get_block({term(), term()}) :: {:ok, %Block{}} | :error
  def get_block({uri, hash}) do
    get(uri <> "/block/#{hash}", :block)
  end

  def post(peer, data, uri) do
    send_to_peer(data, "#{peer}/#{uri}")
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

  def get_account_balance({uri, acc}) do
    get(uri <> "/balance/#{acc}", :balance)
  end

  @spec get_account_txs({term(), term()}) :: {:ok, list()} | :error
  def get_account_txs({uri, acc}) do
    get(uri <> "/tx_pool/#{acc}", :acc_txs)
  end

  def get(uri, identifier) do
    case(HTTPoison.get(uri, [{"peer_port", get_local_port()}])) do
      {:ok, %{body: body, headers: headers, status_code: 200}} ->
        case(identifier) do
          :block ->
            response = Poison.decode!(body, as: %Block{}, keys: :atoms!)
            {:ok, response}
          :info ->
            response = Poison.decode!(body, keys: :atoms!)
            {_, server} = Enum.find(headers, fn(header) ->
              header == {"server", "aehttpserver"} end)
            response_with_server_header = Map.put(response, :server, server)
            {:ok, response_with_server_header}
          :acc_txs ->
            response = Poison.decode!(body,
              as: [%SignedTx{data: %TxData{}}], keys: :atoms!)
            {:ok, response}
          _ ->
            json_response(body)
        end
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        :error
      {:error, %HTTPoison.Error{}} ->
        :error
    end
  end

  def json_response(body) do
    response = Poison.decode!(body)
    {:ok, response}
  end

  defp send_to_peer(data, uri) do
    HTTPoison.post uri, Poison.encode!(data),
      [{"Content-Type", "application/json"}]
  end

  defp get_local_port() do
    Aehttpserver.Endpoint |> :sys.get_state |> elem(3) |> Enum.at(2)
    |> elem(3) |> elem(2) |> Enum.at(1) |> List.keyfind(:http, 0)
    |> elem(1) |> Enum.at(0) |> elem(1)
  end
end
