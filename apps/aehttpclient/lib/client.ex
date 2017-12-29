defmodule Aehttpclient.Client do
  @moduledoc """
  Client used for making requests to a node.
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.TxData
  alias Aecore.Peers.Worker, as: Peers
  alias Aeutil.Serialization

  require Logger

  @spec get_info(term) :: {:ok, map} | :error
  def get_info(uri) do
    get(uri <> "/info", :info)
  end

  @spec get_block({term, binary}) :: {:ok, Block.t} | {:error, binary}
  def get_block({uri, hash}) do
    hash = Base.encode16(hash)
    case get(uri <> "/block/#{hash}", :block) do
      {:ok, serialized_block} ->
        {:ok, Serialization.block(serialized_block, :deserialize)}
        #TODO handle deserialization errors
      {:error, reason} ->
        {:error, reason}
    end
  end

  def get_pool_txs(uri) do
    get(uri <> "/pool_txs", :pool_txs)
  end

  @spec send_block(Block.t, list(binary)) :: :ok
  def send_block(block, peers) do
    data = Serialization.block(block, :serialize)
    post_to_peers("new_block", data, peers)
  end

  @spec send_tx(SignedTx.t, list(binary)) :: :ok
  def send_tx(tx, peers) do
    data = Serialization.tx(tx, :serialize)
    post_to_peers("new_tx", data, peers)
  end

  @spec post_to_peers(binary, binary, list(binary)) :: :ok
  defp post_to_peers(uri, data, peers) do
    for peer <- peers do
      post(peer, data, uri)
    end
    :ok
  end

  defp post(peer, data, uri) do
    send_to_peer(data, "#{peer}/#{uri}")
  end

  @spec get_peers(term) :: {:ok, list()}
  def get_peers(uri) do
    get(uri <> "/peers")
  end

  @spec get_and_add_peers(term) :: :ok
  def get_and_add_peers(uri) do
    {:ok, peers} = get_peers(uri)
    Enum.each(peers, fn{peer, _} -> Peers.add_peer(peer) end)
  end

  @spec get_account_balance({binary, binary}) :: {:ok, binary} | :error
  def get_account_balance({uri, acc}) do
    get(uri <> "/balance/#{acc}")
  end

  @spec get_account_txs({term, term}) :: {:ok, list()} | :error
  def get_account_txs({uri, acc}) do
    get(uri <> "/tx_pool/#{acc}", :acc_txs)
  end

  @spec get(binary, term) :: {term, struct}
  defp get(uri, identifier \\ :default) do
    case(HTTPoison.get(uri, [{"peer_port", get_local_port()}, {"nonce", Peers.get_peer_nonce()}])) do
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
          :pool_txs ->
            response =
              body
              |> Poison.decode!(as: [%SignedTx{data: %TxData{}}], keys: :atoms!)
              |> Enum.map(fn(tx) -> Serialization.tx(tx, :deserialize) end)
            {:ok, response}
          :default ->
            json_response(body)
        end
      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Response 404"}
      {:ok, %HTTPoison.Response{status_code: 400}} ->
        {:error, "Response 400"}
      {:error, %HTTPoison.Error{}} ->
        {:error, "HTTPPoison Error"}
      unexpected ->
        Logger.error(fn -> "unexpected client result " <> Kernel.inspect(unexpected) end)
        {:error, "Unexpected error"}
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
    Aehttpserver.Web.Endpoint |> :sys.get_state() |> elem(3) |> Enum.at(2)
    |> elem(3) |> elem(2) |> Enum.at(1) |> List.keyfind(:http, 0)
    |> elem(1) |> Enum.at(0) |> elem(1)
  end
end
