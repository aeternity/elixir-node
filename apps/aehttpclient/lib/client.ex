defmodule Aehttpclient.Client do
  @moduledoc """
  Client used for making requests to a node.
  """

  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Tx.SignedTx
  alias Aecore.Tx.DataTx
  alias Aecore.Keys.Peer, as: PeerKeys
  alias Aeutil.Serialization

  require Logger

  @typedoc "Client request identifier"
  @type req_kind :: :default | :pool_txs | :acc_txs | :info | :block | :raw_blocks

  @spec get_info(term()) :: {:ok, map()} | :error
  def get_info(uri) do
    get(uri <> "/info", :info)
  end

  @spec get_peer_info(term()) :: {:ok, map()} | :error
  def get_peer_info(uri) do
    case get(uri <> "/peer_info") do
      {:ok, %{"port" => port, "pubkey" => pubkey}} ->
        decoded_pubkey = PeerKeys.base58c_decode(pubkey)
        host = uri |> String.split(":") |> Enum.at(0) |> to_charlist()
        peer_info = %{host: host, port: port, pubkey: decoded_pubkey}
        {:ok, peer_info}

      {:error, _reason} = error ->
        error
    end
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

  @spec get_peers(term()) :: {:ok, list()}
  def get_peers(uri) do
    get(uri <> "/peers")
  end

  @spec get_account_txs({term(), term()}) :: {:ok, list()} | :error
  def get_account_txs({uri, acc}) do
    get(uri <> "/tx_pool/#{acc}", :acc_txs)
  end

  @spec handle_response(req_kind(), map() | list(), list(map())) :: {:ok, map()}
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
      |> Enum.map(fn tx -> SignedTx.deserialize(tx) end)

    {:ok, response}
  end

  defp handle_response(:default, body, _headers) do
    response = Poison.decode!(body)
    {:ok, response}
  end

  @spec get(binary(), req_kind) :: {:ok, map()} | {:error, binary()}
  defp get(uri, identifier \\ :default) do
    case HTTPoison.get(uri) do
      {:ok, %{body: body, headers: headers, status_code: 200}} ->
        handle_response(identifier, body, headers)

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        {:error, "Response 404"}

      {:ok, %HTTPoison.Response{status_code: 400}} ->
        {:error, "Response 400"}

      {:error, %HTTPoison.Error{} = error} ->
        {:error, "HTTPPoison Error #{inspect(error)}"}

      unexpected ->
        Logger.error(fn ->
          "unexpected client result " <> inspect(unexpected)
        end)

        {:error, "Unexpected error"}
    end
  end
end
