defmodule Aecore.Peers.PeerBlocksTask do
  use Task

  alias Aecore.Peers.Sync
  alias Aecore.Peers.Scheduler

  def start_link(arg) do
    Task.start_link(__MODULE__, :run, [arg])
  end

  def run([peer_uri, from_block_hash]) do
    Scheduler.add_running_task()
    Sync.add_peer_blocks_to_sync_state(peer_uri, from_block_hash)
    Sync.add_valid_peer_blocks_to_chain()
    Scheduler.remove_running_task()
  end
end
