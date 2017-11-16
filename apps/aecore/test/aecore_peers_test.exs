defmodule AecorePeersTest do

  use ExUnit.Case

  alias Aecore.Peers.Worker, as: Peers

  setup do
    Peers.start_link([])
    []
  end

  test "add peer, get all peers, check peers and remove the peer" do
    assert {:error, "Equal peer nonces"} = Peers.add_peer("localhost:4000")
    assert Enum.count(Peers.all_peers) == 0
    assert :ok = Peers.check_peers
    assert {:error, "Peer not found"} =
      Peers.remove_peer("localhost:4000")
  end

end
