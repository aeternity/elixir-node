defmodule AecorePeersTest do

  use ExUnit.Case

  alias Aecore.Peers.Worker, as: Peers

  setup do
    Peers.start_link()
    []
  end

  test "add peer, get all peers, check peers and remove the peer" do
    assert :ok = Peers.add_peer("localhost:4000")
    Peers.add_peer("localhost:4000")
    assert Enum.count(Peers.all_peers) == 1
    assert :ok = Peers.check_peers
    assert :ok = Peers.remove_peer("localhost:4000")
    assert {:error, "Peer not found"} = Peers.remove_peer("localhost:4001")
  end

end
