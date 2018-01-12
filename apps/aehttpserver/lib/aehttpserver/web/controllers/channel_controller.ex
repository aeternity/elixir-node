defmodule Aehttpserver.Web.ChannelController do
  use Aehttpserver.Web, :controller

  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Structures.ChannelTxData
  alias Aecore.Structures.MultisigTx
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aeutil.Serialization

  def invite(conn, _params) do
    lock_amount = conn.body_params["lock_amount"]
    peer_port_headers = Plug.Conn.get_req_header(conn, "peer_port")
    peer_ip = conn.peer |> elem(0) |> Tuple.to_list |> Enum.join(".")
    peer_port = peer_port_headers |> Enum.at(0) |> to_string()
    peer_uri = peer_ip <> ":" <> peer_port
    Peers.add_channel_invite(peer_uri, lock_amount)

    json conn, %{:status => :ok}
  end

  def accept(conn, _params) do
    deserialized_lock_amounts =
      Serialization.serialize_keys(conn.body_params["data"]["lock_amounts"], :deserialize)
    tx_data = ChannelTxData.new(%{conn.body_params["data"] |
                                  "lock_amounts" => deserialized_lock_amounts,
                                  "fee" => 10})
    {:ok, pubkey} = Keys.pubkey()
    {:ok, signature} = Keys.sign(tx_data)
    updated_signatures =
      conn.body_params["signatures"]
      |> Serialization.serialize_map(:deserialize)
      |> Map.put(pubkey, signature)
    updated_multisig_tx =
      MultisigTx.new(data: tx_data, signatures: updated_signatures)
    Pool.add_transaction(updated_multisig_tx)

    json conn, %{:status => :ok}
  end

end
