defmodule Aecore.Peers.Worker.Supervisor do
  @moduledoc """
  Supervises the Peers, PeerConnectionSupervisor, Sync and ranch acceptor processes with a one_for_all strategy
  """

  use Supervisor

  alias Aecore.Sync.Sync
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.PeerConnection
  alias Aecore.Peers.Worker.PeerConnectionSupervisor
  alias Aecore.Keys

  @spec start_link([
          {:debug, [:log | :statistics | :trace | {any(), any()}]}
          | {:name, atom() | {:global, any()} | {:via, atom(), any()}}
          | {:spawn_opt,
             :link
             | :monitor
             | {:fullsweep_after, non_neg_integer()}
             | {:min_bin_vheap_size, non_neg_integer()}
             | {:min_heap_size, non_neg_integer()}
             | {:priority, :high | :low | :normal}}
          | {:timeout, :infinity | non_neg_integer()}
        ]) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok)
  end

  def init(:ok) do
    {pubkey, privkey} = Keys.keypair(:peer)

    children = [
      Sync,
      PeerConnectionSupervisor,
      Peers,
      :ranch.child_spec(
        :peer_pool,
        num_of_acceptors(),
        :ranch_tcp,
        [port: sync_port()],
        PeerConnection,
        %{
          port: sync_port(),
          privkey: privkey,
          pubkey: pubkey
        }
      )
    ]

    Supervisor.init(children, strategy: :one_for_all)
  end

  def sync_port do
    Application.get_env(:aecore, :peers)[:sync_port]
  end

  def num_of_acceptors do
    Application.get_env(:aecore, :peers)[:ranch_acceptors]
  end
end
