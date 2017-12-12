defmodule Aehttpserver.InfoController do
  use Aehttpserver.Web, :controller

  alias Aecore.Structures.Block
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Peers.Worker, as: Peers

  require Logger

  def info(conn, _params) do
    latest_block = Chain.latest_block()
    latest_block_header = latest_block.header
      |> BlockValidation.block_header_hash()
      |> Base.encode16()

    genesis_block_header = Block.genesis_block().header
    genesis_block_hash = genesis_block_header
     |> BlockValidation.block_header_hash()
     |> Base.encode16()

    peer_nonce = Peers.get_peer_nonce()

    {:ok, pubkey} = Keys.pubkey()
    pubkey = Base.encode16(pubkey)

    #Add whoever's getting our info
    peer_ip = conn.peer |> elem(0) |> Tuple.to_list |> Enum.join(".")
    peer_port = Plug.Conn.get_req_header(conn, "peer_port") |> Enum.at(0) |> to_string()
    peer_port = ":" <> peer_port
    host_port = ":" <> to_string(conn.port)
    peer = peer_ip <> peer_port
    host = conn.host <> host_port

    if !(peer == host || host == "localhost:" <> host_port) do
      case(Map.has_key?(Peers.all_peers, peer)) do
        true ->
          Logger.info("Peer already in our list")
        false ->
          Peers.schedule_add_peer(peer)
      end
    end

    json(conn, %{current_block_version: latest_block.header.version,
                 current_block_height: latest_block.header.height,
                 current_block_hash: latest_block_header,
                 genesis_block_hash: genesis_block_hash,
                 difficulty_target: latest_block.header.difficulty_target,
                 public_key: pubkey,
                 peer_nonce: peer_nonce})

  end
end
