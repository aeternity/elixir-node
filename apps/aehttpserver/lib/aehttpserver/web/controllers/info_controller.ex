defmodule Aehttpserver.Web.InfoController do
  use Aehttpserver.Web, :controller

  alias Aecore.Chain.{Header, Genesis}
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys
  alias Aecore.Account.Account

  require Logger

  def info(conn, _params) do
    top_block = Chain.top_block()

    top_block_header =
      top_block.header
      |> Header.hash()
      |> Header.base58c_encode()

    genesis_block_header = Genesis.block().header

    genesis_block_hash =
      genesis_block_header
      |> Header.hash()
      |> Header.base58c_encode()

    {sign_pubkey, _} = Keys.keypair(:sign)
    pubkey_hex = Account.base58c_encode(sign_pubkey)

    {peer_pubkey, _} = Keys.keypair(:peer)
    peer_pubkey_hex = Keys.peer_encode(peer_pubkey)

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
    json(conn, %{
      pubkey:
        :sign
        |> Keys.keypair()
        |> elem(0)
        |> Account.base58c_encode()
    })
  end
end
