defmodule Aehttpserver.Web.InfoController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation
  alias Aecore.Keys.Wallet
  alias Aecore.Keys.Peer, as: PeerKeys
  alias Aecore.Account.Account

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

    pubkey = Wallet.get_public_key()
    pubkey_hex = Account.base58c_encode(pubkey)

    {peer_pubkey, _} = PeerKeys.keypair()
    peer_pubkey_hex = PeerKeys.base58c_encode(peer_pubkey)

    json(conn, %{
      current_block_version: top_block.header.version,
      current_block_height: top_block.header.height,
      current_block_hash: top_block_header,
      genesis_block_hash: genesis_block_hash,
      target: top_block.header.target,
      public_key: pubkey_hex,
      peer_pubkey: peer_pubkey_hex
    })
  end

  def public_key(conn, _params) do
    json(conn, %{pubkey: Account.base58c_encode(Wallet.get_public_key())})
  end
end
