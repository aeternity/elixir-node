defmodule Aecore.Peers.SyncNew do
  @moduledoc """
  This module is responsible for the Sync logic between Peers to share blocks between eachother
  """

  use GenServer

  alias Aecore.Chain.Header
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Persistence.Worker, as: Persistence

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

  @type peer_id_map :: %{peer: String.t()}

  @typedoc "List of all the syncing peers"
  @type sync_pool :: list(sync_peer())

  @type hash_pool :: {{non_neg_integer(), non_neg_integer()}, Block.t() | peer_id_map()}

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

  @spec forward_block(Block.t(), String.t()) :: :ok | {:error, String.t()}
  def forward_block(block, peer_id) do
    GenServer.call(__MODULE__, {:forward_block, block, peer_id})
  end

  @spec forward_tx(SignedTx.t(), String.t()) :: :ok | {:error, String.t()}
  def forward_tx(tx, peer_id) do
    GenServer.call(__MODULE__, {:forward_tx, tx, peer_id})
  end

  ## INNER FUNCTIONS ##

  def handle_cast({:start_sync, peer_id, remote_hash}, _from, state) do
    case sync_in_progress?(peer_id) do
      false ->
        do_start_sync(peer_id, remote_hash)

      true ->
        Logger.info("#{__MODULE__}: sync is already in progress with #{inspect(peer_id)}")
    end

    {:noreply, state}
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
    result =
      case Enum.find(list, false, fn peer -> Map.get(peer, :id) == peer_id end) do
        false ->
          false

        peer ->
          {true, peer}
      end

    {:no_reply, result, state}
  end

  def handle_call({:forward_block, block, peer_id}, _from, state) do
    {:no_reply, do_forward_block(block, peer_id), state}
  end

  def handle_call({:forward_tx, tx, peer_id}, _from, state) do
    {:no_reply, do_forward_tx(tx, peer_id), state}
  end

  @spec insert_header(sync_peer(), sync_pool()) :: {true | false, sync_pool()}
  defp insert_header(
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

  ## TODO: Fix the return value
  @spec do_start_sync(String.t(), binary()) :: String.t()
  defp do_start_sync(peer_id, remote_hash) do
    case get_header_by_hash(peer_id, remote_hash) do
      {:ok, remote_header} ->
        remote_height = remote_header.height
        local_height = Chain.top_height()
        {:ok, genesis_block} = Chain.get_block_by_height(0)
        min_agreed_hash = genesis_block.header.height
        max_agreed_height = min(local_height, remote_height)

        {agreed_height, agreed_hash} =
          agree_on_height(
            peer_id,
            remote_header,
            remote_height,
            max_agreed_height,
            min_agreed_hash
          )

        case new_header?(peer_id, remote_header, agreed_height, agreed_hash) do
          false ->
            # Already syncing with this peer
            :ok

          true ->
            # TODO: pool_result = fill_pool(peer_id, agreed_hash)
            # TODO: fetch_more(peer_id, agreed_height, agreed_hash, pool_result)
            :ok
        end

      {:error, reason} ->
        Logger.error("#{__MODULE__}: Fetching top block from
        #{inspect(peer_id)} failed with: #{inspect(reason)} ")
    end
  end

  defp do_forward_block(block, peer_id) do
    height = block.header.height

    case sync_in_progress?(peer_id) do
      {true, %{to: to_height}} when to_height > height + @max_diff_for_sync ->
        Logger.debug("#{__MODULE__}: Not forwarding to #{inspect(peer_id)}, too far ahead")

      false ->
        # send_block(peer_id, block) Send block through the peer module
        :ok
    end
  end

  defp do_forward_tx(tx, peer_id) do
    send_tx(peer_id, tx)
    Logger.debug("#{__MODULE__}: sent tx: #{inspect(tx)} to peer #{inspect(peer_id)}")
  end

  @spec agree_on_height(String.t(), binary(), non_neg_integer(), non_neg_integer(), binary())
  defp agree_on_height(_peer_id, _r_header, _r_height, l_height, agreed_hash) when l_height == 0 do
    {0, agreed_hash}
  end

  defp agree_on_height(peer_id, r_header, r_height, l_height, agreed_hash)
       when r_height == l_height do
    r_hash = r_header.root_hash

    case Persistence.get_block_by_hash(r_hash) do
      {:ok, _} ->
        # We agree on this block height
        {r_height, r_hash}

      _ ->
        # We are on a fork
        agree_on_height(peer_id, r_header, r_height, l_height - 1, agreed_hash)
    end
  end

  defp agree_on_height(peer_id, r_header, r_height, l_height, agreed_hash)
       when r_height != l_height do
    case get_header_by_height(peer_id, l_height) do
      {:ok, header} ->
        agree_on_height(peer_id, header, l_height, l_height, agreed_hash)

      {:error, reason} ->
        {0, agreed_hash}
    end
  end
end
