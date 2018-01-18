defmodule Aehttpserver.Web.ChannelController do
  use Aehttpserver.Web, :controller

  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Structures.ChannelTxData
  alias Aecore.Structures.MultisigTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aeutil.Serialization
  alias Aehttpclient.Client

  require Logger

  def invite(conn, _params) do
    lock_amount = conn.body_params["lock_amount"]
    fee = conn.body_params["fee"]
    peer_uri = get_peer_uri_from_conn(conn)
    case Client.get_info(peer_uri) do
      {:ok, info} ->
        peer_pubkey = Base.decode16!(info.public_key)
        Peers.add_channel_invite(peer_pubkey, peer_uri, lock_amount, fee)

        json conn, %{:status => :ok}
      {:error, message} ->
        Logger.error(fn ->
            "Couldn't get info from #{peer_uri} - #{message}"
          end)

        json conn, %{:status => :error}
    end
  end

  def accept(conn, _params) do
    peer_uri = get_peer_uri_from_conn(conn)
    case Client.get_info(peer_uri) do
      {:ok, info} ->
        {:ok, pubkey} = Keys.pubkey()
        peer_pubkey = Base.decode16!(info.public_key)
        {_, peer_lock_amount} =
          Enum.find(conn.body_params["data"]["lock_amounts"], fn{address, _} ->
              address != pubkey
            end)
        deserialized_lock_amounts =
          Serialization.serialize_keys(conn.body_params["data"]["lock_amounts"], :deserialize)
        fee = conn.body_params["data"]["fee"]
        tx_data = ChannelTxData.new(%{conn.body_params["data"] |
                                      "lock_amounts" => deserialized_lock_amounts,
                                      "fee" => fee})
        {:ok, signature} = Keys.sign(tx_data)
        updated_signatures =
          conn.body_params["signatures"]
          |> Serialization.serialize_map(:deserialize)
          |> Map.put(pubkey, signature)
        updated_multisig_tx =
          MultisigTx.new(data: tx_data, signatures: updated_signatures)
        Peers.add_channel_invite(peer_pubkey, peer_uri, peer_lock_amount, fee)
        Pool.add_transaction(updated_multisig_tx)

        json conn, %{:status => :ok}
      {:error, message} ->
        Logger.error(fn ->
            "Couldn't get info from #{peer_uri} - #{message}"
          end)

        json conn, %{:status => :error}
    end
  end

  def payment_proposal(conn, _params) do
    peer_uri = get_peer_uri_from_conn(conn)
    case Client.get_info(peer_uri) do
      {:ok, info} ->
        peer_pubkey = Base.decode16!(info.public_key)
        deserialized_tx = build_multisig_tx(conn)
        Peers.add_pending_tx(peer_pubkey, deserialized_tx)

        json conn, %{:status => :ok}
      {:error, message} ->
        Logger.error(fn ->
            "Couldn't get info from #{peer_uri} - #{message}"
          end)

        json conn, %{:status => :error}
    end
  end

  def payment_acceptance(conn, _params) do
    peer_uri = get_peer_uri_from_conn(conn)
    case Client.get_info(peer_uri) do
      {:ok, info} ->
        peer_pubkey = Base.decode16!(info.public_key)
        deserialized_tx = build_multisig_tx(conn)
        Peers.add_channel_tx(peer_pubkey, deserialized_tx)

        json conn, %{:status => :ok}
      {:error, message} ->
        Logger.error(fn ->
            "Couldn't get info from #{peer_uri} - #{message}"
          end)

        json conn, %{:status => :error}
    end
  end

  def open_channels(conn, _params) do
    hex_addresses =
      Peers.open_channels
      |> Map.keys
      |> Enum.map(fn(address) -> Base.encode16(address) end)
    json conn, hex_addresses
  end

  def build_multisig_tx(conn) do
    deserialized_lock_amounts =
      Serialization.serialize_keys(conn.body_params["data"]["lock_amounts"], :deserialize)
    fee = conn.body_params["data"]["fee"]
    tx_data = ChannelTxData.new(%{conn.body_params["data"] |
                                  "lock_amounts" => deserialized_lock_amounts,
                                  "fee" => fee})
    deserialized_signatures =
    Serialization.serialize_map(conn.body_params["signatures"], :deserialize)
    MultisigTx.new(data: tx_data, signatures: deserialized_signatures)
  end

  defp get_peer_uri_from_conn(conn) do
    peer_port_headers = Plug.Conn.get_req_header(conn, "peer_port")
    peer_ip = conn.peer |> elem(0) |> Tuple.to_list |> Enum.join(".")
    peer_port = peer_port_headers |> Enum.at(0) |> to_string()
    peer_ip <> ":" <> peer_port
  end

end
