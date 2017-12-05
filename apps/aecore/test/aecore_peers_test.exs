defmodule AecorePeersTest do

  use ExUnit.Case

  alias Aecore.Peers.Worker, as: Peers

  setup do
    Peers.start_link([])
    []
  end

  @tag :peers
  test "add peer, get all peers, check peers and remove the peer" do
    assert Enum.empty?(Peers.all_peers)
    assert :ok = Peers.check_peers
    assert {:error, "Peer not found"} =
      Peers.remove_peer("localhost:4000")
  end

end
