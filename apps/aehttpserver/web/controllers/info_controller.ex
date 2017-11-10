defmodule Aehttpserver.InfoController do
  use Aehttpserver.Web, :controller

  alias Aecore.Structures.Block
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.Scheduler, as: Scheduler

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

    json conn, %{current_block_version: latest_block.header.version,
                 current_block_height: latest_block.header.height,
                 current_block_hash: latest_block_header,
                 genesis_block_hash: genesis_block_hash,
                 difficulty_target: latest_block.header.difficulty_target,
                 public_key: pubkey,
                 peer_nonce: peer_nonce}
  end
end
