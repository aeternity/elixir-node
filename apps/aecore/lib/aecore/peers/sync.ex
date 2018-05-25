defmodule Aecore.Peers.Sync do
  @moduledoc """
  This module is responsible for the Sync logic between Peers to share blocks between eachother
  """

  use GenServer

  alias Aecore.Chain.Header
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Peers.PeerConnection
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Peers.Events
  alias Aeutil.Scientific
  alias Aecore.Tx.Pool.Worker, as: Pool

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

  @type block_map :: %{block: Block.t()}

  @typedoc "List of all the syncing peers"
  @type sync_pool :: list(sync_peer())

  @typedoc "List of tuples of block height and block hash connected to a given block or peer"
  @type hash_pool :: list({{non_neg_integer(), non_neg_integer()}, block_map() | peer_id_map()})

  @max_headers_per_chunk 100
  @max_diff_for_sync 50
  @max_adds 20

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
    Events.subscribe(:block_created)
    Events.subscribe(:tx_created)
    Events.subscribe(:top_changed)

    :ok = :jobs.add_queue(:sync_jobs, [:passive])
    {:ok, state}
  end

  @doc """
  Starts a synchronizing process between our node and the node of the given peer_id
  """
  @spec start_sync(String.t(), binary()) :: :ok | {:error, String.t()}
  def start_sync(peer_id, remote_hash) do
    GenServer.cast(__MODULE__, {:start_sync, peer_id, remote_hash})
  end

  @spec fetch_mempool(String.t()) :: :ok | {:error, String.t()}
  def fetch_mempool(peer_id) do
    GenServer.cast(__MODULE__, {:fetch_mempool, peer_id})
  end

  @spec schedule_ping(String.t()) :: :ok | {:error, String.t()}
  def schedule_ping(peer_id) do
    GenServer.cast(__MODULE__, {:schedule_ping, peer_id})
  end

  def delete_from_pool(peer_id) do
    GenServer.cast(__MODULE__, {:delete_from_pool, peer_id})
  end

  def state do
    GenServer.call(__MODULE__, :state)
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

  @spec fetch_next(String.t(), non_neg_integer(), binary(), any()) :: tuple()
  def fetch_next(peer_id, height_in, hash_in, result) do
    GenServer.call(__MODULE__, {:fetch_next, peer_id, height_in, hash_in, result}, 30_000)
  end

  @spec forward_block(Block.t(), String.t()) :: :ok | {:error, String.t()}
  def forward_block(block, peer_id) do
    GenServer.cast(__MODULE__, {:forward_block, block, peer_id})
  end

  @spec forward_tx(SignedTx.t(), String.t()) :: :ok | {:error, String.t()}
  def forward_tx(tx, peer_id) do
    GenServer.cast(__MODULE__, {:forward_tx, tx, peer_id})
  end

  @spec update_hash_pool(list()) :: list()
  def update_hash_pool(hashes) do
    GenServer.call(__MODULE__, {:update_hash_pool, hashes})
  end

  ## INNER FUNCTIONS ##

  def handle_cast({:start_sync, peer_id, remote_hash}, state) do
    :jobs.enqueue(:sync_jobs, {:start_sync, peer_id, remote_hash})
    {:noreply, state}
  end

  def handle_cast({:fetch_mempool, peer_id}, state) do
    :jobs.enqueue(:sync_jobs, {:fetch_mempool, peer_id})
    {:noreply, state}
  end

  def handle_cast({:schedule_ping, peer_id}, state) do
    :jobs.enqueue(:sync_jobs, {:schedule_ping, peer_id})
    {:noreply, state}
  end

  def handle_cast({:delete_from_pool, peer_id}, %{sync_pool: pool} = state) do
    {:noreply, %{state | sync_pool: List.delete(pool, peer_id)}}
  end

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(
        {:new_header, pid, peer_id, header, agreed_height, hash},
        _from,
        %{sync_pool: pool} = state
      ) do
    height = header.height
    difficulty = Scientific.target_to_difficulty(header.target)

    {is_new, new_pool} =
      insert_header(
        SyncNew.new(%{
          difficulty: difficulty,
          from: agreed_height,
          to: height,
          hash: hash,
          peer: peer_id,
          pid: pid
        }),
        pool
      )

    case is_new do
      true ->
        Process.monitor(pid)

      false ->
        :ok
    end

    {:reply, is_new, %{state | sync_pool: new_pool}}
  end

  def handle_call({:sync_in_progress, peer_id}, _from, %{sync_pool: pool} = state) do
    result =
      case Enum.find(pool, false, fn peer -> Map.get(peer, :id) == peer_id end) do
        false ->
          false

        peer ->
          {true, peer}
      end

    {:reply, result, state}
  end

  def handle_cast({:forward_block, block, peer_id}, state) do
    :jobs.enqueue(:sync_jobs, {:forward, %{block: block}, peer_id})
    {:noreply, state}
  end

  def handle_cast({:forward_tx, tx, peer_id}, state) do
    :jobs.enqueue(:sync_jobs, {:forward, %{tx: tx}, peer_id})
    {:noreply, state}
  end

  def handle_call({:update_hash_pool, hashes}, _from, state) do
    hash_pool = merge(state.hash_pool, hashes)
    Logger.debug(fn -> "Hash pool now contains #{inspect(hash_pool)} hashes" end)
    {:reply, :ok, %{state | hash_pool: hash_pool}}
  end

  def handle_call({:fetch_next, peer_id, height_in, hash_in, result}, _from, state) do
    hash_pool =
      case result do
        {:ok, block} ->
          block_height = block.header.height
          block_hash = BlockValidation.block_header_hash(block.header)

          List.keyreplace(
            state.hash_pool,
            {block_height, block_hash},
            0,
            {{block_height, block_hash}, %{block: block}}
          )

        _ ->
          state.hash_pool
      end

    Logger.info("#{__MODULE__}: fetch next from Hashpool")

    case update_chain_from_pool(height_in, hash_in, hash_pool) do
      {:error, reason} ->
        Logger.info("#{__MODULE__}: Chain update failed: #{inspect(reason)}")
        {:reply, {:error, :sync_stopped}, %{state | hash_pool: hash_pool}}

      {:ok, new_height, new_hash, []} ->
        Logger.debug(fn -> "Got all the blocks from Hashpool" end)

        case Enum.find(state.sync_pool, false, fn peer -> Map.get(peer, :id) == peer_id end) do
          false ->
            ## abort sync
            {:reply, {:error, :sync_stopped}, %{state | hash_pool: []}}

          %{to: to} when to <= new_height ->
            new_sync_pool =
              Enum.reject(state.sync_pool, fn peers -> Map.get(peers, :id) == peer_id end)

            {:reply, :done, %{state | hash_pool: [], sync_pool: new_sync_pool}}

          _peer ->
            {:reply, {:fill_pool, new_height, new_hash}, %{state | hash_pool: []}}
        end

      {:ok, new_height, new_hash, new_hash_pool} ->
        sliced_hash_pool =
          for {{height, hash}, %{peer: _id}} <- new_hash_pool do
            {height, hash}
          end

        case sliced_hash_pool do
          [] ->
            ## We have all blocks
            {:reply, {:insert, new_height, new_hash}, %{state | hash_pool: new_hash_pool}}

          pick_from_hashes ->
            {_pick_height, pick_hash} = Enum.random(pick_from_hashes)

            {:reply, {:fetch, new_height, new_hash, pick_hash},
             %{state | hash_pool: new_hash_pool}}
        end
    end
  end

  def handle_info({:gproc_ps_event, event, %{info: info}}, state) do
    case event do
      :block_created -> enqueue(:forward, %{status: :created, block: info})
      :tx_created -> enqueue(:forward, %{status: :created, tx: info})
      :top_changed -> enqueue(:forward, %{status: :top_changed, block: info})
      :tx_received -> enqueue(:forward, %{status: :received, tx: info})
    end

    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, state) do
    Logger.info("Worker stopped with reason: ~p", [reason])
    new_state = Enum.filter(state, fn x -> x.pid == pid end)
    {:noreply, new_state}
  end

  def handle_info(_, state) do
    {:noreply, state}
  end

  @spec update_chain_from_pool(non_neg_integer(), binary(), list()) :: tuple()
  defp update_chain_from_pool(agreed_height, agreed_hash, hash_pool) do
    case split_hash_pool(agreed_height + 1, agreed_hash, hash_pool, [], 0) do
      {_, _, [], rest, n_added} when rest != [] and n_added < @max_adds ->
        {:error, {:stuck_at, agreed_height + 1}}

      {new_agreed_height, new_agreed_hash, same, rest, _} ->
        {:ok, new_agreed_height, new_agreed_hash, same ++ rest}
    end
  end

  @spec split_hash_pool(non_neg_integer(), binary(), list(), any(), non_neg_integer()) :: tuple()
  defp split_hash_pool(height, prev_hash, [{{h, _}, _} | hash_pool], same, n_added)
       when h < height do
    split_hash_pool(height, prev_hash, hash_pool, same, n_added)
  end

  defp split_hash_pool(height, prev_hash, [{{h, hash}, map} = item | hash_pool], same, n_added)
       when h == height and n_added < @max_adds do
    case Map.get(map, :block) do
      nil ->
        split_hash_pool(height, prev_hash, hash_pool, [item | same], n_added)

      block ->
        hash = BlockValidation.block_header_hash(block.header)

        case block.header.prev_hash do
          prev_hash ->
            case Chain.add_block(block) do
              :ok ->
                split_hash_pool(h + 1, hash, hash_pool, [], n_added + 1)

              {:error, _} ->
                split_hash_pool(height, prev_hash, hash_pool, same, n_added)
            end
        end
    end
  end

  defp split_hash_pool(height, prev_hash, hash_pool, same, n_added) do
    {height - 1, prev_hash, same, hash_pool, n_added}
  end

  # Tries to add new peer to the peer_pool.
  # If we have it already, we get either the local or the remote info
  # from the peer with highest from_height.
  # After that we merge the new_sync_peer data with the old one, updating it.
  @spec insert_header(sync_peer(), sync_pool()) :: {true | false, sync_pool()}
  defp insert_header(
         %{
           difficulty: difficulty,
           from: _agreed_height,
           to: _height,
           hash: _hash,
           peer: peer_id,
           pid: _pid
         } = new_sync,
         sync_pool
       ) do
    {new_peer?, new_pool} =
      case Enum.find(sync_pool, false, fn peer -> Map.get(peer, :id) == peer_id end) do
        false ->
          {true, [new_sync | sync_pool]}

        old_sync ->
          new_sync1 =
            case old_sync.from > new_sync.from do
              true ->
                old_sync

              false ->
                new_sync
            end

          max_diff = max(difficulty, old_sync.difficulty)
          max_to = max(new_sync.to, old_sync.to)
          new_sync2 = %{new_sync1 | difficulty: max_diff, to: max_to}
          {false, [new_sync2 | sync_pool]}
      end

    {new_peer?, Enum.sort_by(new_pool, fn peer -> peer.difficulty end)}
  end

  # Here we initiate the actual sync of the Peers. We get the remote Peer values,
  # then we agree on some height, and check weather we agree on it, if not we go lower,
  # until we agree on some height. This might be even the Gensis block!
  @spec do_start_sync(String.t(), binary()) :: String.t()
  defp do_start_sync(peer_id, remote_hash) do
    case PeerConnection.get_header_by_hash(remote_hash, peer_id) do
      {:ok, remote_header} ->
        remote_height = remote_header.height
        local_height = Chain.top_height()
        {:ok, genesis_block} = Chain.get_block_by_height(0)
        min_agreed_hash = BlockValidation.block_header_hash(genesis_block.header)
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
            :ok

          true ->
            pool_result = fill_pool(peer_id, agreed_hash)
            fetch_more(peer_id, agreed_height, agreed_hash, pool_result)
            :ok
        end

      {:error, reason} ->
        Logger.error("#{__MODULE__}: Fetching top block from
                      #{inspect(peer_id)} failed with: #{inspect(reason)} ")
    end
  end

  # With this func we try to agree on block height on which we agree and could sync.
  # In other words a common block.
  @spec agree_on_height(String.t(), binary(), non_neg_integer(), non_neg_integer(), binary()) ::
          tuple()
  defp agree_on_height(_peer_id, _r_header, _r_height, l_height, agreed_hash)
       when l_height == 0 do
    {0, agreed_hash}
  end

  defp agree_on_height(peer_id, r_header, r_height, l_height, agreed_hash)
       when r_height == l_height do
    r_hash = BlockValidation.block_header_hash(r_header)

    case Persistence.get_block_by_hash(r_hash) do
      {:ok, _} ->
        {r_height, r_hash}

      _ ->
        # We are on a fork
        agree_on_height(peer_id, r_header, r_height, l_height - 1, agreed_hash)
    end
  end

  defp agree_on_height(peer_id, _r_header, r_height, l_height, agreed_hash)
       when r_height != l_height do
    case PeerConnection.get_header_by_height(l_height, peer_id) do
      {:ok, header} ->
        agree_on_height(peer_id, header, l_height, l_height, agreed_hash)

      {:error, _reason} ->
        {0, agreed_hash}
    end
  end

  defp fetch_more(peer_id, _, _, :done) do
    ## Chain sync done
    delete_from_pool(peer_id)
  end

  defp fetch_more(peer_id, last_height, _, {:error, error}) do
    Logger.info("Abort sync at height #{last_height} Error: #{error}")
    delete_from_pool(peer_id)
  end

  defp fetch_more(peer_id, last_height, header_hash, result) do
    ## We need to supply the Hash, because locally we might have a shorter,
    ## but locally more difficult fork
    case fetch_next(peer_id, last_height, header_hash, result) do
      {:fetch, new_height, new_hash, hash} ->
        case do_fetch_block(hash, peer_id) do
          {:ok, _, new_block} ->
            fetch_more(peer_id, new_height, new_hash, {:ok, new_block})

          {:error, _} = error ->
            fetch_more(peer_id, new_height, new_hash, error)
        end

      {:insert, new_height, new_hash} ->
        fetch_more(peer_id, new_height, new_hash, :no_result)

      {:fill_pool, agreed_height, agreed_hash} ->
        pool_result = fill_pool(peer_id, agreed_hash)
        fetch_more(peer_id, agreed_height, agreed_hash, pool_result)

      other ->
        fetch_more(peer_id, last_height, header_hash, other)
    end
  end

  def process_jobs do
    result = :jobs.dequeue(:sync_jobs, 1)
    process_job(result)
  end

  defp process_job([{_t, job}]) do
    case job do
      {:forward, %{block: block}, peer_id} ->
        do_forward_block(block, peer_id)

      {:forward, %{tx: tx}, peer_id} ->
        do_forward_tx(tx, peer_id)

      {:start_sync, peer_id, remote_hash} ->
        case sync_in_progress?(peer_id) do
          false -> do_start_sync(peer_id, remote_hash)
          _ -> Logger.info("Sync already in progress")
        end

      {:fetch_mempool, peer_id} ->
        do_fetch_mempool(peer_id)

      {:ping, peer_id} ->
        PeerConnection.ping_peer(peer_id)
        :ok

      _other ->
        Logger.debug(fn -> "Unknown job" end)
    end
  end

  @spec enqueue(atom(), map()) :: list()
  defp enqueue(opts, msg) do
    peers = Peers.get_random(3)

    for peer <- peers do
      :jobs.enqueue(:sync_jobs, {opts, msg, Peers.peer_id(peer)})
    end
  end

  # Send our block to the Remote Peer
  defp do_forward_block(block, peer_id) do
    height = block.header.height

    case sync_in_progress?(peer_id) do
      ## If we are syncing with this peer and it has far more blocks ignore sending
      {true, %{to: remote_height}} when remote_height > height + @max_diff_for_sync ->
        Logger.debug(fn ->
          "#{__MODULE__}: Not forwarding to #{inspect(peer_id)}, too far ahead"
        end)

      _ ->
        ## Send block through the peer module
        PeerConnection.send_new_block(block, peer_id)

        Logger.debug(fn ->
          "#{__MODULE__}: sent block: #{inspect(block)} to peer #{inspect(peer_id)}"
        end)
    end
  end

  # Send a transaction to the Remote Peer
  defp do_forward_tx(tx, peer_id) do
    PeerConnection.send_new_tx(tx, peer_id)
    Logger.debug(fn -> "#{__MODULE__}: sent tx: #{inspect(tx)} to peer #{inspect(peer_id)}" end)
  end

  # Merges the local Hashes with the Remote Peer hashes
  # So it takes the data from where the height is higher
  defp merge([], new_hashes), do: new_hashes
  defp merge(old_hashes, []), do: old_hashes

  defp merge([{{h_1, _hash_1}, _} | old_hashes], [{{h_2, hash_2}, map_2} | new_hashes])
       when h_1 < h_2 do
    merge(old_hashes, [{{h_2, hash_2}, map_2} | new_hashes])
  end

  defp merge([{{h_1, hash_1}, map_1} | old_hashes], [{{h_2, _hash_2}, _} | new_hashes])
       when h_1 > h_2 do
    merge([{{h_1, hash_1}, map_1} | old_hashes], new_hashes)
  end

  defp merge(old_hashes, [{{h_2, hash_2}, map_2} | new_hashes]) do
    pick_same({{h_2, hash_2}, map_2}, old_hashes, new_hashes)
  end

  defp pick_same({{h, hash_2}, map_2}, [{{h, hash_1}, map_1} | old_hashes], new_hashes) do
    case hash_1 == hash_2 do
      true ->
        [
          {{h, hash_1}, Map.merge(map_1, map_2)}
          | pick_same({{h, hash_2}, map_2}, old_hashes, new_hashes)
        ]

      false ->
        [{{h, hash_1}, map_1} | pick_same({{h, hash_2}, map_2}, old_hashes, new_hashes)]
    end
  end

  defp pick_same(_, old_hashes, new_hashes), do: merge(old_hashes, new_hashes)

  defp fill_pool(peer_id, agreed_hash) do
    case PeerConnection.get_n_successors(agreed_hash, @max_headers_per_chunk, peer_id) do
      {:ok, []} ->
        delete_from_pool(peer_id)
        :done

      {:ok, chunk_hashes} ->
        hash_pool =
          for chunk <- chunk_hashes do
            {chunk, %{peer: peer_id}}
          end

        update_hash_pool(hash_pool)
        {:filled_pool, length(chunk_hashes) - 1}

      _err ->
        delete_from_pool(peer_id)
        {:error, :sync_abort}
    end
  end

  # Check if we already have this block locally, is so
  # take it from the chain
  defp do_fetch_block(hash, peer_id) do
    case Chain.get_block(hash) do
      {:ok, block} ->
        Logger.debug(fn -> "#{__MODULE__}: We already have this block!" end)
        {:ok, false, block}

      {:error, _} ->
        do_fetch_block_ext(hash, peer_id)
    end
  end

  # If we don't have the block locally, take it from the Remote Peer
  defp do_fetch_block_ext(hash, peer_id) do
    case PeerConnection.get_block(hash, peer_id) do
      {:ok, block} ->
        case BlockValidation.block_header_hash(block.header) === hash do
          true ->
            Logger.debug(fn ->
              "#{__MODULE__}: Block #{inspect(block)} fetched from #{inspect(peer_id)}"
            end)

            {:ok, true, block}

          false ->
            {:error, :hash_mismatch}
        end

      err ->
        Logger.debug(fn -> "#{__MODULE__}: Failed to fetch the block from #{inspect(peer_id)}" end)

        err
    end
  end

  # Try to fetch the pool of transactions
  # from the Remote Peer we are connected to
  defp do_fetch_mempool(peer_id) do
    {:ok, pool} = PeerConnection.get_mempool(peer_id)
    Logger.debug(fn -> "#{__MODULE__}: Mempool received from #{inspect(peer_id)}" end)
    Enum.each(pool, fn {_hash, tx} -> Pool.add_transaction(tx) end)
  end
end
