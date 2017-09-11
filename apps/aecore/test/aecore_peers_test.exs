defmodule AecorePeersTest do
  use ExUnit.Case
  doctest Aecore.Peers.Worker
  alias Aecore.Peers.Worker, as: Peers

  @moduledoc """
  Unit tests for the aec_peers module
  """

  setup do
    Peers.start_link()
    Peers.add_some_peers
    [peers: ""]
  end

  test "all peers" do
    assert {num, _peers} = Peers.all()
    assert :true = is_integer(num)
    assert num > 0
  end

  test "add peer" do
    assert :ok = Peers.add("http://192.168.1.1:8000")
    assert {:ok, %{}} = Peers.info("http://192.168.0.1:8000")
  end

  test "info for peer" do
	assert {:ok, %{}} = Peers.info("http://192.168.0.2:8000")
  end


  test "info for not exsisting peer" do
    assert {:error, _} = Peers.info("http://192.168.254.254:8000")
  end

  test "remove existing peer" do
    assert :ok = Peers.remove("http://192.168.0.1:8000")
    assert {:error, _} = Peers.info("http://192.168.0.1:8000")
  end

  test "get random peer if the tree is not empty" do
    assert {:ok, _} = Peers.get_random
  end

  test "uri from ip and port" do
    assert {:ok,"http://123.123.123.123:1337/"} = Peers.uri_from_ip_port("123.123.123.123","1337")
  end

end
