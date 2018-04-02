defmodule Aehttpclient.Client do
  @moduledoc """
  Client used for making requests to a node.
  """

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.DataTx
  alias Aecore.Peers.Worker, as: Peers
  alias Aeutil.Serialization
  alias Aehttpserver.Web.Endpoint

  require Logger

  @typedoc "Client request identifier"
  @type req_kind :: :default | :pool_txs | :acc_txs | :info | :block | :raw_blocks

  @spec handle_response(req_kind(), map(), list(map())) :: {:ok, map()}

  @spec get_info(term()) :: {:ok, map()} | :error
  def get_info(uri) do
    get(uri <> "/info", :info)
  end

  @spec get_block({term(), binary()}) :: {:ok, Block.t()} | {:error, binary()}
  def get_block({uri, hash}) do
    hash = Header.base58c_encode(hash)

    case get(uri <> "/block-by-hash?hash=#{hash}", :block) do
      {:ok, serialized_block} ->
        {:ok, Serialization.block(serialized_block, :deserialize)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec get_raw_blocks({term(), binary(), binary()}) :: {:ok, term()} | {:error, binary()}
  def get_raw_blocks({uri, from_block_hash, to_block_hash}) do
    from_block_hash = Header.base58c_encode(from_block_hash)
    to_block_hash = Header.base58c_encode(to_block_hash)

    uri =
      uri <> "/raw_blocks?" <> "from_block=" <> from_block_hash <> "&to_block=" <> to_block_hash

    get(uri, :raw_blocks)
  end

  def get_pool_txs(uri) do
    get(uri <> "/pool_txs", :pool_txs)
  end

  @spec send_block(Block.t(), list(binary())) :: :ok
  def send_block(block, peers) do
    data = Serialization.block(block, :serialize)
    post_to_peers("block", data, peers)
  end

  @spec send_tx(SignedTx.t(), list(binary())) :: :ok
  def send_tx(tx, peers) do
    data = Serialization.tx(tx, :serialize)
    post_to_peers("tx", data, peers)
  end

  @spec post_to_peers(String.t(), binary(), list(String.t())) :: :ok
  defp post_to_peers(uri, data, peers) do
    Enum.each(peers, fn peer ->
      post(peer, data, uri)
    end)
  end

  defp post(peer, data, uri) do
    send_to_peer(data, "#{peer}/#{uri}")
  end

  @spec get_peers(term()) :: {:ok, list()}
  def get_peers(uri) do
    get(uri <> "/peers")
  end

  @spec get_and_add_peers(term()) :: :ok
  def get_and_add_peers(uri) do
    {:ok, peers} = get_peers(uri)
    Enum.each(peers, fn {peer, _} -> Peers.add_peer(peer) end)
  end

  @spec get_account_balance({binary(), binary()}) :: {:ok, binary()} | :error
  def get_account_balance({uri, acc}) do
    get(uri <> "/balance/#{acc}")
  end

  @spec get_account_txs({term(), term()}) :: {:ok, list()} | :error
  def get_account_txs({uri, acc}) do
    get(uri <> "/tx_pool/#{acc}", :acc_txs)
  end

  defp handle_response(:block, body, _headers) do
    response = Poison.decode!(body)
    {:ok, response}
  end

  defp handle_response(:raw_blocks, body, _headers) do
    response = Poison.decode!(body)

    deserialized_blocks =
      Enum.map(response, fn block ->
        Serialization.block(block, :deserialize)
      end)

    {:ok, deserialized_blocks}
  end

  defp handle_response(:info, body, headers) do
    response = Poison.decode!(body, keys: :atoms!)

    {_, server} =
      Enum.find(headers, fn header ->
        header == {"server", "aehttpserver"}
      end)

    response_with_server_header = Map.put(response, :server, server)
    {:ok, response_with_server_header}
  end

  defp handle_response(:acc_txs, body, _headers) do
    response = Poison.decode!(body, as: [%SignedTx{data: %DataTx{}}], keys: :atoms!)
    {:ok, response}
  end

  defp handle_response(:pool_txs, body, _headers) do
    response =
      body
      |> Poison.decode!()
      |> Enum.map(fn tx -> Serialization.tx(tx, :deserialize) end)

    {:ok, response}
  end

  defp handle_response(:default, body, _headers) do
    response = Poison.decode!(body)
    {:ok, response}
  end

  @spec get(binary(), req_kind) :: {:ok, map()} | {:error, binary()}
  defp get(uri, identifier \\ :default) do
    case HTTPoison.get(uri, [{"peer_port", get_local_port()}, {"nonce", Peers.get_peer_nonce()}]) do
      {:ok, %{body: body, headers: headers, status_code: 200}} ->
        handle_response(identifier, body, headers)

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Response 404"}

      {:ok, %HTTPoison.Response{status_code: 400}} ->
        {:error, "Response 400"}

      {:error, %HTTPoison.Error{}} ->
        {:error, "HTTPPoison Error"}

      unexpected ->
        Logger.error(fn ->
          "unexpected client result " <> Kernel.inspect(unexpected)
        end)

        {:error, "Unexpected error"}
    end
  end

  defp send_to_peer(data, uri) do
    HTTPoison.post(uri, Poison.encode!(data), [
      {"Content-Type", "application/json"}
    ])
  end

  # TODO: what is this function even doing?
  defp get_local_port() do
    Endpoint.url() |> String.split(":") |> Enum.at(-1)
  end
end
