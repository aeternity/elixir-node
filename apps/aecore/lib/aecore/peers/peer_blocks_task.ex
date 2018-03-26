defmodule Aecore.Peers.PeerBlocksTask do
  @moduledoc """
  A task which gets unknown blocks from a given peer URI and starting block hash and adds
  those blocks to the chain if a sync isn't in progress.
  """

  use Task

  alias Aecore.Peers.Sync

  def start_link(args) do
    Task.start_link(__MODULE__, :run, [args])
  end

  def run([peer_uri, from_block_hash]) do
    Sync.add_peer_blocks_to_sync_state(peer_uri, from_block_hash)
    Sync.add_valid_peer_blocks_to_chain(Sync.get_peer_blocks())
  end
end
