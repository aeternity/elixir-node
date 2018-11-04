defmodule Aehttpserver.Web.PeersController do
  use Aehttpserver.Web, :controller

  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Account.Account
  alias Aecore.Keys
  alias Aeutil.Environment

  def info(conn, _params) do
    sync_port = String.to_integer(Environment.get_env_or_default("SYNC_PORT", "3015"))

    peer_pubkey =
      :peer
      |> Keys.keypair()
      |> elem(0)
      |> Keys.peer_encode()

    json(conn, %{port: sync_port, pubkey: peer_pubkey})
  end

  def peers(conn, _params) do
    peers = Peers.all_peers()

    serialized_peers =
      Enum.map(peers, fn peer -> %{peer | pubkey: Account.base58c_encode(peer.pubkey)} end)

    json(conn, serialized_peers)
  end
end
