defmodule Aecore.Peers.SyncNew do
  @moduledoc """
  This module is responsible for the Sync logic between Peers to share blocks between eachother
  """

  use GenServer

  require Logger

  @typedoc "Structure of a peer to sync with"
  @type sync_peer :: %{
          difficulty: non_neg_integer(),
          from: non_neg_integer(),
          to: non_neg_integer(),
          hash: binary(),
          peer: String.t(),
          pid: binary()
        }

  @typedoc "List of all the syncing peers"
  @type sync_pool :: list(sync_peer())

  defstruct difficulty: nil,
            from: nil,
            to: nil,
            hash: nil,
            peer: nil,
            pid: nil

  use ExConstructor

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{:sync_pool => [], :hash_pool => []}, name: __MODULE__)
  end

  def init(state) do
    {:ok, state}
  end

  @doc """
  Starts a synchronizing process between our node and the node of the given peer_id
  """
  @spec start_sync(String.t(), binary(), non_neg_integer()) :: :ok | {:error, String.t()}
  def start_sync(peer_id, remote_hash, remote_difficulty) do
    GenServer.cast(__MODULE__, {:start_sync, peer_id, remote_hash, remote_difficulty})
  end

  @doc """
  Checks weather the sync is in progress
  """
  @spec sync_in_progress?(String.t()) :: {true | false, non_neg_integer}
  def sync_in_progress?(peer_id) do
    GenServer.call(__MODULE__, {:sync_in_progress, peer_id})
  end

  @spec new_header?(String.t(), Header.t(), non_neg_integer(), binary()) :: true | false
  def new_header?(peer_id, header, agreed_height, hash) do
    GenServer.call(__MODULE__, {:new_header, self(), peer_id, header, agreed_height, hash})
  end

  ## INNER FUNCTIONS ##

  def handle_cast({:start_sync, peer_id, remote_hash, remote_difficulty}, _from, state) do
  end

  def handle_call(
        {:new_header, pid, peer_id, header, agreed_height, hash},
        _from,
        %{sync_pool: pool} = state
      ) do
    height = header.height
    difficulty = header.difficulty

    {is_new, new_pool} =
      insert_header(
        SyncNew.new(
          %{
            difficulty: difficulty,
            from: agreed_height,
            to: height,
            hash: hash,
            peer: peer_id,
            pid: pid
          },
          pool
        )
      )

    case is_new do
      true ->
        # do something with process
        :ok

      false ->
        :ok
    end

    {:no_reply, is_new, %{state | sync_pool: new_pool}}
  end

  def handle_call({:sync_in_progress, peer_id}, _from, %{sync_pool: pool} = state) do
    {:no_reply, {Map.has_key?(pool, peer_id), peer_id}, state}
  end

  @spec insert_header(sync_peer(), sync_pool()) :: {true | false, sync_pool()}
  def insert_header(
        %{
          difficulty: difficulty,
          from: agreed_height,
          to: height,
          hash: hash,
          peer: peer_id,
          pid: pid
        } = new_sync,
        sync_pool
      ) do
    {new_peer?, new_pool} =
      case Enum.find(sync_pool, false, fn peer -> Map.get(peer, :id) == peer_id end) do
        false ->
          {true, [new_sync | sync_pool]}

        old_sync ->
          new_sync1 =
            case old_sync.from > from do
              true ->
                old_sync

              false ->
                new_sync
            end

          max_diff = max(difficulty, old_sync.difficulty)
          max_to = max(to, old_sync.to)
          new_sync2 = %{new_sync1 | difficulty: max_diff, to: max_to}
          new_pool = List.delete(sync_pool, old_sync)

          {false, [new_sync2 | sync_pool]}
      end

    {new_peer?, Enum.sort_by(new_pool, fn peer -> peer.difficulty end)}
  end
end
