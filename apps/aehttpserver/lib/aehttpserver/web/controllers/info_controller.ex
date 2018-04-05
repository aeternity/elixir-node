defmodule Aehttpserver.Web.InfoController do
  use Aehttpserver.Web, :controller

  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Structures.Account
  alias Plug.Conn

  require Logger

  def info(conn, _params) do
    top_block = Chain.top_block()

    top_block_header =
      top_block.header
      |> BlockValidation.block_header_hash()
      |> Header.base58c_encode()

    genesis_block_header = Block.genesis_block().header

    genesis_block_hash =
      genesis_block_header
      |> BlockValidation.block_header_hash()
      |> Header.base58c_encode()

    own_nonce = Peers.get_peer_nonce()

    pubkey = Wallet.get_public_key()
    pubkey_hex = Account.base58c_encode(pubkey)

    # Add whoever's getting our info
    peer_port_headers = Conn.get_req_header(conn, "peer_port")
    peer_nonce_headers = Conn.get_req_header(conn, "nonce")

    if !Enum.empty?(peer_port_headers) && !Enum.empty?(peer_nonce_headers) do
      peer_ip = conn.peer |> elem(0) |> Tuple.to_list() |> Enum.join(".")
      peer_port = peer_port_headers |> Enum.at(0) |> to_string()
      peer_port_with_colon = ":" <> peer_port
      peer_nonce = peer_nonce_headers |> Enum.at(0) |> String.to_integer()
      peer = peer_ip <> peer_port_with_colon

      unless peer_nonce == own_nonce do
        Peers.schedule_add_peer(peer, peer_nonce)
      end
    end

    json(conn, %{
      current_block_version: top_block.header.version,
      current_block_height: top_block.header.height,
      current_block_hash: top_block_header,
      genesis_block_hash: genesis_block_hash,
      target: top_block.header.target,
      public_key: pubkey_hex,
      peer_nonce: own_nonce
    })
  end

  def public_key(conn, _params) do
    json(conn, %{pubkey: Account.base58c_encode(Wallet.get_public_key())})
  end
end
