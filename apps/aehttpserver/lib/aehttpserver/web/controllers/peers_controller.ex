defmodule Aehttpserver.Web.PeersController do
  use Aehttpserver.Web, :controller

  alias Aecore.Peers.Worker, as: Peers

  def info(conn, _params) do
    peers = Peers.all_peers()
    json conn, peers
  end
end
