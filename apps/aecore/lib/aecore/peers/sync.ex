defmodule Aecore.Peers.Sync do
  @moduledoc """
  This module is responsible for the Sync logic between Peers to share blocks between eachother
  """

  use GenServer

  alias __MODULE__
  alias Aecore.Chain.{Header, BlockValidation}
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Peers.PeerConnection
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Peers.Jobs
  alias Aeutil.Events
  alias Aecore.Peers.Worker, as: Peers
  alias Aeutil.Scientific

  require Logger

  @typedoc "Structure of a peer to sync with"
  @type sync_peer :: %{
          difficulty: non_neg_integer(),
          from: non_neg_integer(),
          to: non_neg_integer(),
          hash: binary(),
          peer: pid(),
          pid: pid()
        }

  @type peer_pid_map :: %{peer: pid()}

  @type block_map :: %{block: Block.t()}

  @typedoc "List of all the syncing peers"
  @type sync_pool :: list(sync_peer())

  @typedoc "List of tuples of block height and block hash connected to a given block or peer"
  @type hash_pool :: list({{non_neg_integer(), non_neg_integer()}, block_map() | peer_pid_map()})

  @max_headers_per_chunk 100
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
    Events.subscribe(:new_top_block)
    Events.subscribe(:tx_created)
    Events.subscribe(:top_changed)

    :ok = Jobs.add_queue(:sync_jobs)
    {:ok, state}
  end

  def state do
    GenServer.call(__MODULE__, :state)
  end

  @doc """
  Starts a synchronizing process between our node and the node of the given peer_pid
  """
  @spec start_sync(pid(), binary()) :: :ok | {:error, String.t()}
  def start_sync(peer_pid, remote_hash) do
    Jobs.enqueue(:sync_jobs, {:start_sync, peer_pid, remote_hash})
  end

  @doc """
  Fetches the remote Pool of transactions
  """
  @spec fetch_mempool(pid()) :: :ok | {:error, String.t()}
  def fetch_mempool(peer_pid) do
    GenServer.call(__MODULE__, {:fetch_mempool, peer_pid})
  end

  @doc """
  Checks weather the sync is in progress
  """
  @spec sync_in_progress?(pid()) :: false | {true, non_neg_integer}
  def sync_in_progress?(peer_pid) do
    GenServer.call(__MODULE__, {:sync_in_progress, peer_pid})
  end

  @spec add_peer?(pid(), Header.t(), non_neg_integer(), binary()) :: true | false
  def add_peer?(peer_pid, header, agreed_height, hash) do
    GenServer.call(__MODULE__, {:is_new_peer, self(), peer_pid, header, agreed_height, hash})
  end

  @doc """
  Does the fetching of the blocks depending on the hash_pool.
  """
  @spec fetch_next(pid(), non_neg_integer(), binary(), any()) :: :done | tuple()
  def fetch_next(peer_pid, height_in, hash_in, result) do
    GenServer.call(__MODULE__, {:fetch_next, peer_pid, height_in, hash_in, result}, 30_000)
  end

  @spec update_hash_pool(list()) :: list(Header.t())
  def update_hash_pool(hashes) do
    GenServer.call(__MODULE__, {:update_hash_pool, hashes})
  end

  def delete_from_pool(peer_pid) do
    GenServer.cast(__MODULE__, {:delete_from_pool, peer_pid})
  end

  ## INNER FUNCTIONS ##

  def handle_call(:state, _from, state) do
    {:reply, state, state}
  end

  def handle_call({:fetch_mempool, peer_pid}, _from, state) do
    :ok = Jobs.enqueue(:sync_jobs, {:fetch_mempool, peer_pid})
    {:reply, :ok, state}
  end

  def handle_call(
        {:is_new_peer, process_pid, peer_pid, header, agreed_height, hash},
        _from,
        %{sync_pool: pool} = state
      ) do
    height = header.height
    difficulty = Scientific.target_to_difficulty(header.target)

    {new?, new_pool} =
      try_add_peer(
        Sync.new(%{
          difficulty: difficulty,
          from: agreed_height,
          to: height,
          hash: hash,
          peer: peer_pid,
          pid: process_pid
        }),
        pool
      )

    if new? do
      Process.monitor(process_pid)
    else
      :ok
    end

    {:reply, new?, %{state | sync_pool: new_pool}}
  end

  def handle_call({:sync_in_progress, peer_pid}, _from, %{sync_pool: pool} = state) do
    result =
      case Enum.find(pool, false, fn peer -> Map.get(peer, :pid) == peer_pid end) do
        false ->
          false

        peer ->
          {true, peer}
      end

    {:reply, result, state}
  end

  def handle_call({:update_hash_pool, hashes}, _from, state) do
    hash_pool = merge(state.hash_pool, hashes)
    Logger.debug(fn -> "#{__MODULE__}: Hash pool now contains #{inspect(hash_pool)} hashes" end)
    {:reply, :ok, %{state | hash_pool: hash_pool}}
  end

  def handle_call({:fetch_next, peer_pid, inc_height, inc_hash, result}, _from, state) do
    hash_pool =
      case result do
        {:ok, block} ->
          block_height = block.header.height
          block_hash = BlockValidation.block_header_hash(block.header)

          # If the hash of this block does not fit wanted hash, it is discarded
          # (In case we ask for block with hash X and we get a block with hash Y)
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

    case update_chain_from_pool(inc_height, inc_hash, hash_pool) do
      {:error, reason} ->
        Logger.info("#{__MODULE__}: Chain update failed: #{inspect(reason)}")
        {:reply, {:error, reason}, %{state | hash_pool: hash_pool}}

      {:ok, new_height, new_hash, []} ->
        Logger.debug(fn -> "#{__MODULE__}: Got all the blocks from Hashpool" end)

        # The sync might be done. Check for more blocks.
        case Enum.find(state.sync_pool, false, fn peer -> Map.get(peer, :id) == peer_pid end) do
          false ->
            # Abort sync, we don't have this peer in our list anymore.
            {:reply, {:error, :unknown_peer}, %{state | hash_pool: []}}

          %{to: to} when to <= new_height ->
            # We are done!
            new_sync_pool =
              Enum.reject(state.sync_pool, fn peers -> Map.get(peers, :id) == peer_pid end)

            {:reply, :done, %{state | hash_pool: [], sync_pool: new_sync_pool}}

          _peer ->
            # This peer has more blocks to give. Fetch them!
            {:reply, {:fill_pool, new_height, new_hash}, %{state | hash_pool: []}}
        end

      {:ok, new_height, new_hash, new_hash_pool} ->
        sliced_hash_pool =
          for {{height, hash}, %{peer: _id}} <- new_hash_pool do
            {height, hash}
          end

        case sliced_hash_pool do
          [] ->
            # We have all blocks. Just insertion left
            {:reply, {:insert, new_height, new_hash}, %{state | hash_pool: new_hash_pool}}

          pick_from_hashes ->
            # We still have blocks to fetch.
            {_pick_height, picked_hash} = Enum.random(pick_from_hashes)

            {:reply, {:fetch, new_height, new_hash, picked_hash},
             %{state | hash_pool: new_hash_pool}}
        end
    end
  end

  def handle_cast({:delete_from_pool, peer_pid}, %{sync_pool: pool} = state) do
    {:noreply, %{state | sync_pool: Enum.filter(pool, fn peer -> peer.peer != peer_pid end)}}
  end

  def handle_info({:gproc_ps_event, event, %{info: info}}, state) do
    case event do
      :new_top_block ->
        if not Enum.empty?(Peers.all_pids()) do
          enqueue(:forward, %{status: :created, block: info})
        end

      :tx_created ->
        enqueue(:forward, %{status: :created, tx: info})

      :top_changed ->
        enqueue(:forward, %{status: :top_changed, block: info})

      :tx_received ->
        enqueue(:forward, %{status: :received, tx: info})
    end

    Jobs.dequeue(:sync_jobs)
    {:noreply, state}
  end

  def handle_info({:DOWN, _ref, :process, pid, reason}, %{sync_pool: sync_pool} = state) do
    Logger.info("#{__MODULE__}: Worker stopped with reason: #{inspect(reason)}")
    {:noreply, %{state | sync_pool: Enum.filter(sync_pool, fn peer -> peer.peer != pid end)}}
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

  @spec split_hash_pool(non_neg_integer(), binary(), hash_pool(), list(), non_neg_integer()) ::
          tuple()
  defp split_hash_pool(height, prev_hash, [{{h, _hash}, _} | hash_pool], same, n_added)
       when h < height do
    split_hash_pool(height, prev_hash, hash_pool, same, n_added)
  end

  defp split_hash_pool(height, prev_hash, [{{h, _hash}, map} = item | hash_pool], same, n_added)
       when h == height and n_added < @max_adds do
    case Map.get(map, :block, :error) do
      :error ->
        split_hash_pool(height, prev_hash, hash_pool, [item | same], n_added)

      block ->
        case Map.get(block.header, :prev_hash, :error) do
          :error ->
            split_hash_pool(height, prev_hash, hash_pool, [item | same], n_added)

          prev_hash ->
            case Chain.add_block(block) do
              :ok ->
                hash = BlockValidation.block_header_hash(block.header)

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
  @spec try_add_peer(sync_peer(), sync_pool()) :: {true, sync_pool()} | {false, sync_pool()}
  defp try_add_peer(
         %{
           difficulty: difficulty,
           from: _agreed_height,
           to: height,
           hash: _hash,
           peer: peer_pid,
           pid: _process_pid
         } = new_peer_data,
         sync_pool
       ) do
    {new_peer?, new_pool} =
      case Enum.find(sync_pool, false, fn peer -> Map.get(peer, :id) == peer_pid end) do
        false ->
          # This peer is new
          {true, [new_peer_data | sync_pool]}

        old_peer_data ->
          # We already have this peer

          peer_data =
            if old_peer_data.from > new_peer_data.from do
              old_peer_data
            else
              new_peer_data
            end

          max_diff = max(difficulty, old_peer_data.difficulty)
          max_height = max(height, old_peer_data.to)
          {false, [%{peer_data | difficulty: max_diff, to: max_height} | sync_pool]}
      end

    {new_peer?, Enum.sort_by(new_pool, fn peer -> peer.difficulty end)}
  end

  # Here we initiate the actual sync of the Peers. We get the remote Peer values,
  # then we agree on some height, and check weather we agree on it, if not we go lower,
  # until we agree on some height. This might be even the Gensis block!
  @spec do_start_sync(pid(), binary()) :: :ok | {:error, String.t()}
  defp do_start_sync(peer_pid, remote_hash) do
    case PeerConnection.get_header_by_hash(remote_hash, peer_pid) do
      {:ok, %{header: remote_header}} ->
        remote_height = remote_header.height
        local_height = Chain.top_height()

        {:ok, genesis_block} = Chain.get_block_by_height(0)

        min_agreed_hash = BlockValidation.block_header_hash(genesis_block.header)
        max_agreed_height = min(local_height, remote_height)

        {agreed_height, agreed_hash} =
          agree_on_height(
            peer_pid,
            remote_header,
            remote_height,
            max_agreed_height,
            min_agreed_hash
          )

        if add_peer?(peer_pid, remote_header, agreed_height, agreed_hash) do
          pool_result = fill_pool(peer_pid, agreed_hash)
          fetch_more(peer_pid, agreed_height, agreed_hash, pool_result)
        else
          # Sync is already in progress with this peer
          :ok
        end

      {:error, reason} ->
        Logger.error("#{__MODULE__}: Fetching top block from
                      #{inspect(peer_pid)} failed with: #{inspect(reason)} ")
    end
  end

  # With this func we try to agree on block height on which we agree and could sync.
  # In other words a common block.
  @spec agree_on_height(pid(), binary(), non_neg_integer(), non_neg_integer(), binary()) ::
          tuple()
  defp agree_on_height(_peer_pid, _r_header, _r_height, l_height, agreed_hash)
       when l_height == 0 do
    {0, agreed_hash}
  end

  defp agree_on_height(peer_pid, r_header, r_height, l_height, agreed_hash)
       when r_height == l_height do
    r_hash = BlockValidation.block_header_hash(r_header)

    case Chain.get_block(r_hash) do
      {:ok, _} ->
        {r_height, r_hash}

      _ ->
        # We are on a fork
        agree_on_height(peer_pid, r_header, r_height, l_height - 1, agreed_hash)
    end
  end

  defp agree_on_height(peer_pid, _r_header, r_height, l_height, agreed_hash)
       when r_height != l_height do
    case PeerConnection.get_header_by_height(l_height, peer_pid) do
      {:ok, %{header: header}} ->
        agree_on_height(peer_pid, header, l_height, l_height, agreed_hash)

      {:error, _reason} ->
        {0, agreed_hash}
    end
  end

  defp fetch_more(peer_pid, _, _, :done) do
    ## Chain sync done
    delete_from_pool(peer_pid)
    :ok
  end

  defp fetch_more(peer_pid, last_height, _, {:error, reason}) do
    Logger.info("#{__MODULE__}: Abort sync at height #{last_height} Error: #{inspect(reason)}")
    delete_from_pool(peer_pid)
    {:error, reason}
  end

  # The result variable represents what action should be made
  defp fetch_more(peer_pid, last_height, header_hash, result) do
    ## We need to supply the Hash, because locally we might have a shorter,
    ## but locally more difficult fork
    case fetch_next(peer_pid, last_height, header_hash, result) do
      {:fetch, new_height, new_hash, picked_hash} ->
        case do_fetch_block(picked_hash, peer_pid) do
          {:ok, new_block} ->
            fetch_more(peer_pid, new_height, new_hash, {:ok, new_block})

          {:error, _} = error ->
            fetch_more(peer_pid, new_height, new_hash, error)
        end

      {:insert, new_height, new_hash} ->
        fetch_more(peer_pid, new_height, new_hash, :no_result)

      {:fill_pool, agreed_height, agreed_hash} ->
        pool_result = fill_pool(peer_pid, agreed_hash)
        fetch_more(peer_pid, agreed_height, agreed_hash, pool_result)

      other ->
        fetch_more(peer_pid, last_height, header_hash, other)
    end
  end

  def process_jobs([]) do
    "No more jobs to do"
  end

  def process_jobs([{_t, job} | t]) do
    case job do
      {:forward, %{block: block}, peer_pid} ->
        PeerConnection.send_new_block(block, peer_pid)

      {:forward, %{tx: tx}, peer_pid} ->
        PeerConnection.send_new_tx(tx, peer_pid)

      {:start_sync, peer_pid, remote_hash} ->
        case sync_in_progress?(peer_pid) do
          false -> do_start_sync(peer_pid, remote_hash)
          _ -> Logger.info("#{__MODULE__}: Sync already in progress")
        end

      {:fetch_mempool, peer_pid} ->
        do_fetch_mempool(peer_pid)

      _other ->
        Logger.debug(fn -> "#{__MODULE__}: Unknown job" end)
    end

    process_jobs(t)
  end

  @spec enqueue(atom(), map()) :: list()
  defp enqueue(opts, msg) do
    Enum.each(Peers.all_pids(), fn pid ->
      Jobs.enqueue(:sync_jobs, {opts, msg, pid})
    end)
  end

  # Merges the local Hashes with the remote (peer) Hashes
  # in such a way that it takes the data from where the height is higher
  defp merge([], new_hashes), do: new_hashes
  defp merge(old_hashes, []), do: old_hashes

  defp merge([{{l_h, _l_hash}, _} | old_hashes], [{{r_h, r_hash}, r_map} | new_hashes])
       when l_h < r_h do
    merge(old_hashes, [{{r_h, r_hash}, r_map} | new_hashes])
  end

  defp merge([{{l_h, l_hash}, l_map} | old_hashes], [{{r_h, _r_hash}, _} | new_hashes])
       when l_h > r_h do
    merge([{{l_h, l_hash}, l_map} | old_hashes], new_hashes)
  end

  defp merge(old_hashes, [{{r_h, r_hash}, r_map} | new_hashes]) do
    pick_same({{r_h, r_hash}, r_map}, old_hashes, new_hashes)
  end

  defp pick_same({{h, r_hash}, r_map}, [{{h, l_hash}, l_map} | old_hashes], new_hashes) do
    case l_hash == r_hash do
      true ->
        [
          {{h, l_hash}, Map.merge(l_map, r_map)}
          | pick_same({{h, r_hash}, r_map}, old_hashes, new_hashes)
        ]

      false ->
        [
          {{h, l_hash}, l_map}
          | pick_same({{h, r_hash}, r_map}, old_hashes, new_hashes)
        ]
    end
  end

  defp pick_same(_, old_hashes, new_hashes), do: merge(old_hashes, new_hashes)

  defp fill_pool(peer_pid, agreed_hash) do
    case PeerConnection.get_n_successors(agreed_hash, @max_headers_per_chunk, peer_pid) do
      {:ok, []} ->
        delete_from_pool(peer_pid)
        :done

      {:ok, %{hashes: chunk_hashes}} ->
        hash_pool =
          for %{hash: hash, height: height} <- chunk_hashes do
            {{height, hash}, %{peer: peer_pid}}
          end

        update_hash_pool(hash_pool)
        {:filled_pool, length(chunk_hashes) - 1}

      _err ->
        delete_from_pool(peer_pid)
        {:error, :sync_abort}
    end
  end

  # Check if we already have this block locally, is so
  # take it from the chain
  defp do_fetch_block(hash, peer_pid) do
    case Chain.get_block(hash) do
      {:ok, block} ->
        Logger.debug(fn -> "#{__MODULE__}: We already have this block!" end)
        {:ok, false, block}

      {:error, _} ->
        do_fetch_block_ext(hash, peer_pid)
    end
  end

  # If we don't have the block locally, take it from the Remote Peer
  defp do_fetch_block_ext(hash, peer_pid) do
    case PeerConnection.get_block(hash, peer_pid) do
      {:ok, %{block: block}} ->
        case BlockValidation.block_header_hash(block.header) === hash do
          true ->
            Logger.debug(fn ->
              "#{__MODULE__}: Block #{inspect(block)} fetched from #{inspect(peer_pid)}"
            end)

            {:ok, block}

          false ->
            {:error, :hash_mismatch}
        end

      err ->
        Logger.debug(fn ->
          "#{__MODULE__}: Failed to fetch the block from #{inspect(peer_pid)}"
        end)

        err
    end
  end

  # Try to fetch the pool of transactions
  # from the Remote Peer we are connected to
  defp do_fetch_mempool(peer_pid) do
    {:ok, %{txs: pool}} = PeerConnection.get_mempool(peer_pid)
    Logger.debug(fn -> "#{__MODULE__}: Mempool received from #{inspect(peer_pid)}" end)
    Enum.each(pool, fn tx -> Pool.add_transaction(tx) end)
  end
end
