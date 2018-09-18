defmodule Aecore.Sync.Sync do
  @moduledoc """
  Handle the Sync functionality between different nodes.
  Syncing with every new node starts a worker that it's going to execute its job.
  In other words sync until the biggest remote hash,
  starting from the agreed height -> the point at which we agree on the header hash (it's equal among us)
  """

  use GenServer

  alias Aecore.Sync.{Jobs, Chain, Task}
  alias Aecore.Chain.Header
  alias Aecore.Chain.Worker, as: Chainstate
  alias Aecore.Peers.PeerConnection
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Tx.SignedTx
  alias Aeutil.Events
  alias Aecore.Governance.GenesisConstants, as: Genesis

  alias __MODULE__

  require Logger

  @max_headers_per_chunk 100

  @type chain_id :: reference()
  @type task_id :: reference()
  @type block_height :: non_neg_integer()
  @type header_hash :: binary()
  @type peer_id :: pid()
  @type last_result ::
          :none
          | {:agreed_height, Chain.chain()}
          | {:hash_pool, list(Task.pool_elem())}
          | {:get_block, block_height(), header_hash(), peer_id(), {:ok, Block.t()}}
          | {:post_blocks, :ok | {:error, Block.t(), block_height()}}
  @type t :: %Sync{sync_tasks: list(Task.t())}

  defstruct sync_tasks: []

  ### ===================================================
  ### API calls
  ### ===================================================

  def start_sync(peer_id, remote_hash) do
    if sync_in_progress?(peer_id) do
      Logger.info("#{__MODULE__}: Already syncing with #{inspect(peer_id)}")
    else
      GenServer.cast(__MODULE__, {:start_sync, peer_id, remote_hash})
    end
  end

  def schedule_ping(peer_id) do
    GenServer.cast(__MODULE__, {:schedule_ping, peer_id})
  end

  @spec sync_in_progress?(peer_id) :: true | false
  def sync_in_progress?(peer_id) do
    GenServer.call(__MODULE__, {:sync_in_progress, peer_id})
  end

  @doc """
  Check weather the given chain is already existing in Task.
  If the chain is unknown (new), create a new Task for it.
  If the chain is inconclusive, we need more data to determine
  weather it is existing or new.
  """
  @spec known_chain(Chain.t(), Chain.t() | :none) ::
          {:inconclusive, Chain.t()}
          | {:existing, Task.task_id()}
          | {:new, Chain.t(), Task.task_id()}
  def known_chain(chain, extra_info) do
    GenServer.call(__MODULE__, {:known_chain, chain, extra_info})
  end

  def update_sync_task(update, task) do
    GenServer.call(__MODULE__, {:update_sync_task, update, task})
  end

  def get_next_work_item(task, peer_id, last_result) do
    GenServer.call(__MODULE__, {:get_next_work_item, task, peer_id, last_result})
  end

  def handle_worker(task_id, action) do
    GenServer.cast(__MODULE__, {:handle_worker, task_id, action})
  end

  ### ==================================================================
  ### GenServer functions
  ### ==================================================================

  ## When we Ping a node with at least as much difficulty as we have,
  ## then we are going to sync with it.
  ## We already agree upon the genesis block and need to find the highest common
  ## block we agree upon. We use a binary search to find out.
  ## From the height we agree upon, we start asking for blocks to add to the chain.
  ##
  ## When an additional Ping arrives for which we agree upon genesis, we have
  ## the following possibilities:
  ## 1. It has worst top hash than our node, do not include in sync
  ## 2. It has better top hash than our node
  ##    We binary search for a block that we agree upon (could be genesis)
  ## We add new node to sync pool to sync agreed block upto top of new
  ## 1. If we are already synchronizing, we ignore it,
  ##    the ongoing sync will pick that up later
  ## 2. If we are not already synchronizing, we start doing so.
  ##
  ## We sync with several nodes at the same time and use as strategy
  ## to pick a random hash from the hashes in the pool.

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %Sync{sync_tasks: []}, name: __MODULE__)
  end

  def init(state) do
    ## Subscribe to receive if we have mined/received new block
    ## and if new tx is created/received
    Events.subscribe(:new_top_block)
    Events.subscribe(:tx_created)

    ## Init the jobs queues
    Jobs.init_queues()

    ## Set trap_exit, to receive crash messages from async processes
    Process.flag(:trap_exit, true)

    {:ok, state}
  end

  def handle_call({:sync_in_progress, peer_id}, _from, state) do
    {:reply, peer_in_sync?(state, peer_id), state}
  end

  def handle_call(
        {:known_chain, %Chain{chain_id: chain_id} = chain, new_chain_info},
        _from,
        state
      ) do
    {new_chain, updated_state} =
      case new_chain_info do
        :none ->
          {chain, state}

        %Chain{chain_id: cid} when cid == chain_id ->
          {Chain.merge_chains(chain, new_chain_info), state}

        %Chain{chain_id: _cid} ->
          {chain, Chain.add_chain_info(new_chain_info, state)}
      end

    {res, new_state} = sync_task_for_chain(new_chain, updated_state)
    {:reply, res, new_state}
  end

  def handle_call({:update_sync_task, update, task_id}, _from, state) do
    new_state = Task.do_update_sync_task(state, task_id, update)
    {:reply, :ok, new_state}
  end

  def handle_call({:get_next_work_item, task_id, peer_id, {:error, _reason}}, _from, state) do
    new_state = Task.do_update_sync_task(state, task_id, {:error, peer_id})
    {:reply, :abort_work, new_state}
  end

  def handle_call({:get_next_work_item, task_id, peer_id, last_result}, _from, state) do
    state_applied_last_result = handle_last_result(state, task_id, last_result)

    {reply, state_applied_next_work_item} =
      do_get_next_work_item(state_applied_last_result, task_id, peer_id)

    {:reply, reply, state_applied_next_work_item}
  end

  ## Handle casts

  def handle_cast({:start_sync, peer_id, remote_header_hash}, state) do
    Jobs.run_job(:sync_task_workers, fn -> do_start_sync(peer_id, remote_header_hash) end)
    {:noreply, state}
  end

  def handle_cast({:schedule_ping, peer_id}, state) do
    if peer_in_sync?(state, peer_id) do
      :ok
    else
      Jobs.run_job(:sync_ping_workers, fn -> ping_peer(peer_id) end)
    end

    {:noreply, state}
  end

  def handle_cast({:handle_worker, task_id, action}, state) do
    new_state =
      case Task.get_sync_task(task_id, state) do
        {:ok, task} ->
          updated_task = do_handle_worker(action, task)
          Task.set_sync_task(updated_task, state)

        {:error, :not_found} ->
          state
      end

    {:noreply, new_state}
  end

  def handle_cast(_, state), do: {:noreply, state}

  def handle_info({:gproc_ps_event, event, %{info: info}}, state) do
    peer_ids = Peers.all_pids()
    non_syncing_peer_ids = Enum.filter(peer_ids, fn pid -> not peer_in_sync?(state, pid) end)

    case event do
      :new_top_block -> Jobs.enqueue(:block, info, non_syncing_peer_ids)
      :tx_created -> Jobs.enqueue(:tx, info, peer_ids)
      :tx_received -> Jobs.enqueue(:tx, info, peer_ids)
      _ -> :ignore
    end

    {:noreply, state}
  end

  def handle_info({:EXIT, pid, :normal}, state) do
    {:noreply, terminate_worker(pid, state)}
  end

  def handle_info({:EXIT, pid, reason}, state) do
    ## It might be one of our syncing workers that crashed
    Logger.info("#{__MODULE__}: Worker stopped with reason: #{inspect(reason)}")
    {:noreply, terminate_worker(pid, state)}
  end

  @doc """
  Try matching this chain to already existent Task.
  If this chain doesn't match any task chain, then we
  create a seperate task for it. (This chain is probably a fork)
  """
  @spec sync_task_for_chain(Chain.t(), Sync.t()) ::
          {:inconclusive, Chain.t(), {:get_header, chain_id(), peer_id(), block_height()}}
          | {{:existing, Task.task_id()}, Sync.t()}
          | {{:new, Chain.t(), Task.task_id()}, Sync.t()}
  def sync_task_for_chain(chain, %Sync{sync_tasks: tasks} = state) do
    case Task.match_chain_to_task(chain, tasks, []) do
      :no_match ->
        ## Starting new task for the given chain
        ## We are here if this is out first task
        ## or if the given chain is a fork
        task = %Task{id: task_id} = Task.init_sync_task(chain)
        {{:new, chain, task_id}, Task.set_sync_task(task, state)}

      {:match, %Task{id: task_id, chain: matched_chain} = task} ->
        ## The given chain matches the chain in the current Task
        ## Merge the chains (possibly get more blocks if the new chain is longer)
        new_chain = Chain.merge_chains(%Chain{chain | chain_id: task_id}, matched_chain)
        updated_task = %Task{task | chain: new_chain}
        {{:existing, task_id}, Task.set_sync_task(updated_task, state)}

      {:inconclusive, _, _} = res ->
        {res, state}
    end
  end

  @doc """
  Act upon the received result. In most cases update the given task.
  """
  @spec handle_last_result(Sync.t(), Task.task_id(), last_result()) :: Sync.t()
  def handle_last_result(state, task_id, last_result) do
    case Task.get_sync_task(task_id, state) do
      {:ok, task} ->
        updated_task = handle_last_result(task, last_result)
        Task.maybe_end_sync_task(state, updated_task)

      {:error, :not_found} ->
        state
    end
  end

  def handle_last_result(task, :none), do: task

  def handle_last_result(%Task{agreed: nil} = task, {:agreed_height, agreed}),
    do: %Task{task | agreed: agreed}

  def handle_last_result(%Task{pool: []} = task, {:hash_pool, hash_pool}) do
    {block_height, header_hash, false} = List.last(hash_pool)
    %Task{task | pool: hash_pool, agreed: %{height: block_height, hash: header_hash}}
  end

  def handle_last_result(%Task{} = task, {:hash_pool, _hash_pool}), do: task

  def handle_last_result(
        %Task{pool: pool} = task,
        {:get_block, block_height, header_hash, peer_id, {:ok, block}}
      ) do
    pool_with_added_block =
      Enum.map(pool, fn
        {^block_height, _, _} -> {block_height, header_hash, {peer_id, block}}
        elem -> elem
      end)

    %Task{task | pool: pool_with_added_block}
  end

  def handle_last_result(%Task{} = task, {:post_blocks, :ok}), do: %Task{task | adding: []}

  def handle_last_result(
        %Task{adding: adds, pending: pends, pool: pool, chain: chain} = task,
        {:post_blocks, {:error, block_from_peer_id, block_height}}
      ) do
    ## Put back the blocks we did not manage to post, and schedule
    ## failing block for another retrieval
    [{block_height, header_hash, _} | put_back] =
      Enum.filter(adds, fn {height, _, _} -> height < block_height end) ++ pends

    pool_with_scheduled_block = [{block_height, header_hash, false} | put_back] ++ pool

    %Task{
      task
      | adding: [],
        pending: [],
        pool: pool_with_scheduled_block,
        chain: %Chain{chain | peers: chain.peers -- [block_from_peer_id]}
    }
  end

  @doc """
  Get all elements of the pool where the block is already taken from
  the peer (the third element is not false)
  untill reaching an element whose block hasn't been picked yet.
  """
  @spec split_pool(list(Task.pool_elem())) ::
          {list(Task.pool_elem()), list(Task.pool_elem()) | []}
  def split_pool(pool), do: split_pool(pool, [])

  def split_pool([{_, _, false} | _] = pool, acc), do: {Enum.reverse(acc), pool}

  def split_pool([], acc), do: {Enum.reverse(acc), []}

  def split_pool([p | pool], acc), do: split_pool(pool, [p | acc])

  @doc """
  Depending on the working item that we receive we do various types of jobs.
  We might:
  - send blocks to a peer
  - get blocks from a peer
  - initiate agreement on a height to sync
  - fill our pool from the current height to the target one
  - take a break
  - abort work if there has been some issue
  """
  @spec do_get_next_work_item(Sync.t(), reference(), peer_id()) ::
          {{:post_blocks, Block.t()}
           | {:get_block, block_height(), header_hash()}
           | {:agree_on_height, Chain.chain()}
           | {:fill_pool, header_hash(), header_hash()}
           | :take_a_break
           | :abort_work, Sync.t()}
  def do_get_next_work_item(state, task_id, peer_id) do
    with {:ok, %Task{chain: %Chain{peers: peer_ids}} = task} <-
           Task.get_sync_task(task_id, state),
         true <- Enum.member?(peer_ids, peer_id) do
      {action, updated_task} = do_get_next_work_item(task)
      {action, Task.set_sync_task(task_id, updated_task, state)}
    else
      _ ->
        {:abort_work, state}
    end
  end

  def do_get_next_work_item(%Task{adding: [], pending: [to_add | new_pending]} = task) do
    {{:post_blocks, to_add}, %Task{task | adding: to_add, pending: new_pending}}
  end

  def do_get_next_work_item(%Task{chain: chain, agreed: nil} = task) do
    {{:agree_on_height, chain}, task}
  end

  def do_get_next_work_item(
        %Task{
          pool: [],
          agreed: %{height: block_height, hash: last_header_hash},
          chain: %Chain{chain: chain}
        } = task
      ) do
    target_header_hash =
      Chain.next_known_header_hash(chain, block_height + @max_headers_per_chunk)

    {{:fill_pool, last_header_hash, target_header_hash}, task}
  end

  def do_get_next_work_item(
        %Task{pool: [{_, _, {_, _}} | _] = pool, adding: add, pending: pend} = task
      ) do
    {to_be_added, new_pool} = split_pool(pool)

    cond do
      add == [] ->
        {{:post_blocks, to_be_added}, %Task{task | pool: new_pool, adding: to_be_added}}

      length(pend) < 10 || new_pool != [] ->
        new_pending =
          pend
          |> Enum.reverse()
          |> Enum.reverse([to_be_added])

        do_get_next_work_item(%Task{task | pool: new_pool, pending: new_pending})

      true ->
        {:take_a_break, task}
    end
  end

  def do_get_next_work_item(%Task{pool: [{_, _, false} | _] = pool} = task) do
    # Pick a random block from the ones we don't have already
    pick_from = Enum.filter(pool, fn {_, _, elem} -> elem == false end)

    random =
      pick_from
      |> length()
      |> :rand.uniform()

    {picked_block_height, picked_header_hash, false} = Enum.fetch!(pick_from, random - 1)
    Logger.info("#{__MODULE__}: Get block at height #{picked_block_height}")
    {{:get_block, picked_block_height, picked_header_hash}, task}
  end

  def do_get_next_work_item(%Task{} = task) do
    Logger.info("#{__MODULE__}: Take a break, nothing to do: #{inspect(task)}")
    {:take_a_break, task}
  end

  @doc """
  Handle new worker or change of a proccess related to worker.
  """
  @spec do_handle_worker(
          {:new_worker, peer_id(), pid()}
          | {:change_worker, peer_id(), pid(), pid()},
          Task.t()
        ) :: Task.t()
  def do_handle_worker({:new_worker, worker_peer_id, pid}, %Task{workers: workers} = task) do
    case Enum.filter(workers, fn {peer_id, _} -> peer_id == worker_peer_id end) do
      [] ->
        :ok

      [{_, old_pid}] ->
        Logger.info(
          "#{__MODULE__}: Peer: #{inspect(worker_peer_id)} already has a worker: #{
            inspect(old_pid)
          }"
        )
    end

    Process.link(pid)
    %Task{task | workers: Task.keystore(worker_peer_id, {worker_peer_id, pid}, workers)}
  end

  def do_handle_worker(
        {:change_worker, worker_peer_id, old_worker_pid, new_worker_pid},
        %Task{workers: workers} = task
      ) do
    case Enum.filter(workers, fn {peer_id, _} -> peer_id == worker_peer_id end) do
      [] ->
        Logger.info(
          "#{__MODULE__}: Missing worker #{old_worker_pid} for peer #{inspect(worker_peer_id)}"
        )

      [{_, ^old_worker_pid}] ->
        :ok

      [{_, another_pid}] ->
        Logger.info(
          "#{__MODULE__}: Wrong worker stored for peer #{inspect(worker_peer_id)} (#{another_pid})"
        )
    end

    Process.link(new_worker_pid)
    # The old worker will terminate right after the call to handle_worker is finished
    # so we can safely remove it
    Process.unlink(old_worker_pid)

    %Task{
      task
      | workers: Task.keystore(worker_peer_id, {worker_peer_id, new_worker_pid}, workers)
    }
  end

  @doc """
  This worker has done it's job,
  remove it from the task that it is related to.
  """
  @spec terminate_worker(pid(), Sync.t()) :: Sync.t()
  def terminate_worker(worker_pid, %Sync{sync_tasks: tasks} = state) do
    case Enum.filter(tasks, fn %{workers: {_, pid}} -> pid == worker_pid end) do
      [task] ->
        worker_pid
        |> terminate_worker(task)
        |> Task.set_sync_task(state)

      [] ->
        state
    end
  end

  def terminate_worker(worker_pid, %Task{workers: workers} = task) do
    [{peer, _}] = Enum.filter(workers, fn {_, pid} -> pid == worker_pid end)
    Logger.info("#{__MODULE__}: Terminating worker: #{worker_pid} for worker: #{peer}")
    %Task{task | workers: Enum.filter(workers, fn {_, pid} -> pid != worker_pid end)}
  end

  @doc """
  Ping a specified peer
  """
  @spec ping_peer(peer_id()) :: :ok | {:error, String.t()}
  def ping_peer(peer_id) do
    case PeerConnection.ping(peer_id) do
      :ok ->
        Logger.info("#{__MODULE__}: Pinged peer #{inspect(peer_id)} successfully")
        :ok

      {:error, reason} = err ->
        Logger.info("#{__MODULE__}: Error while pinging peer #{inspect(peer_id)}: #{reason}")
        err
    end
  end

  @doc """
  Forwards a tx to the specified peer
  """
  @spec forward_block(Block.t(), peer_id()) :: :ok | :error
  def forward_block(block, peer_id) do
    PeerConnection.send_new_block(block, peer_id)
  end

  @doc """
  Forwards a Signed tx to the specified peer
  """
  @spec forward_tx(SignedTx.t(), peer_id()) :: :ok | :error
  def forward_tx(%SignedTx{} = tx, peer_id) do
    PeerConnection.send_new_tx(tx, peer_id)
  end

  defp do_start_sync(peer_id, remote_header_hash) do
    case PeerConnection.get_header_by_hash(remote_header_hash, peer_id) do
      {:ok, %{header: header}} ->
        Logger.info(
          "#{__MODULE__}: New header received from #{inspect(peer_id)}: #{inspect(header)}"
        )

        chain_from_peer_id = Chain.init_chain(peer_id, header)

        ## We do try really hard to identify the same chain here...
        case known_chain(chain_from_peer_id) do
          {:ok, task_id} ->
            handle_worker(task_id, {:new_worker, peer_id, self()})
            work_on_sync_task(peer_id, task_id)

          {:error, reason} ->
            Logger.info(
              "#{__MODULE__}: Could not identify chain, aborting sync with #{inspect(peer_id)}: #{
                reason
              }"
            )
        end

      {:error, reason} ->
        Logger.info(
          "#{__MODULE__}: Fetching top block from #{inspect(peer_id)} failed: #{reason}"
        )
    end
  end

  defp known_chain(chain) do
    chain
    |> known_chain(:none)
    |> identify_chain()
  end

  defp identify_chain({:existing, task}) do
    Logger.info("#{__MODULE__}: Already syncing chain #{inspect(task)}")
    {:ok, task}
  end

  defp identify_chain({:new, %Chain{chain: [target | _]}, task}) do
    Logger.info(
      "#{__MODULE__}: Starting new sync task #{inspect(task)}, target is: #{inspect(target)}"
    )

    {:ok, task}
  end

  defp identify_chain({:inconclusive, chain, {:get_header, chain_id, peers, block_height}}) do
    ## We need another hash for this chain, make sure whoever we ask
    ## is still in this particular chain by including a known (at higher height) hash
    known_header_hash = Chain.next_known_header_hash(chain.chain, block_height)

    case do_get_header_by_height(peers, block_height, known_header_hash) do
      {:ok, %{header: header}} ->
        chain
        |> known_chain(Chain.init_chain(chain_id, peers, header))
        |> identify_chain()

      {:error, _} = err ->
        Logger.info(
          "#{__MODULE__}: Fetching header by height #{block_height}, from #{inspect(peers)} failed"
        )

        err
    end
  end

  defp do_get_header_by_height([], _block_height, _top_header_hash) do
    {:error, :header_not_found}
  end

  defp do_get_header_by_height([peer_id | ids], block_height, top_header_hash) do
    case PeerConnection.get_header_by_height(peer_id, block_height, top_header_hash) do
      {:ok, header} ->
        {:ok, header}

      {:error, reason} ->
        Logger.info(
          "#{__MODULE__}: Fetching header at height #{block_height} under #{
            inspect(top_header_hash)
          } from #{inspect(peer_id)}, failed #{reason}"
        )

        do_get_header_by_height(ids, block_height, top_header_hash)
    end
  end

  defp work_on_sync_task(peer_id, task_id) do
    work_on_sync_task(peer_id, task_id, :none)
  end

  defp work_on_sync_task(peer_id, task_id, last_result) do
    case get_next_work_item(task_id, peer_id, last_result) do
      :take_a_break ->
        fun = fn -> work_on_sync_task(peer_id, task_id) end
        Jobs.delayed_run_job(peer_id, task_id, :sync_task_workers, fun, 250)

      {:agree_on_height, chain} ->
        %Chain{chain: [%{height: top_block_height, hash: top_header_hash} | _]} = chain
        local_block_height = Chainstate.top_height()
        {:ok, %{header: genesis}} = Chainstate.get_block_by_height(0)
        min_agreed_hash = Header.hash(genesis)
        max_agree = min(local_block_height, top_block_height)

        case agree_on_height(
               peer_id,
               top_header_hash,
               top_block_height,
               max_agree,
               max_agree,
               Genesis.height(),
               min_agreed_hash
             ) do
          {:ok, block_height, header_hash} ->
            Logger.info(
              "#{__MODULE__}: Agreed upon height: #{block_height} with #{inspect(peer_id)}"
            )

            agreement = {:agreed_height, %{height: block_height, hash: header_hash}}
            work_on_sync_task(peer_id, task_id, agreement)

          {:error, reason} ->
            work_on_sync_task(peer_id, task_id, {:error, {:agree_on_height, reason}})
        end

      {:fill_pool, start_header_hash, target_header_hash} ->
        fill_pool(peer_id, start_header_hash, target_header_hash, task_id)

      {:post_blocks, blocks} ->
        res = post_blocks(blocks)
        work_on_sync_task(peer_id, task_id, {:post_blocks, res})

      {:get_block, block_height, header_hash} ->
        res =
          case fetch_block(header_hash, peer_id) do
            {:ok, false, _block} ->
              {:get_block, block_height, header_hash, peer_id, {:ok, :local}}

            {:ok, true, block} ->
              {:get_block, block_height, header_hash, peer_id, {:ok, block}}

            {:error, reason} ->
              {:error, {:get_block, reason}}
          end

        work_on_sync_task(peer_id, task_id, res)

      :abort_work ->
        Logger.info("#{__MODULE__}: #{self()} Aborting sync work against #{inspect(peer_id)}")
        schedule_ping(peer_id)
    end
  end

  defp post_blocks([]), do: :ok

  defp post_blocks([{start_height, _, _} | _] = blocks) do
    post_blocks(start_height, start_height, blocks)
  end

  defp post_blocks(from, to, []) do
    Logger.info("#{__MODULE__}: Synced blocks from #{from} to #{to}")
    :ok
  end

  defp post_blocks(from, _to, [{block_height, _header_hash, {_peer_id, :local}} | blocks]) do
    post_blocks(from, block_height, blocks)
  end

  defp post_blocks(from, _to, [{block_height, _header_hash, {peer_id, block}} | blocks]) do
    case Chainstate.add_block(block) do
      :ok ->
        post_blocks(from, block_height, blocks)

      {:error, reason} ->
        Logger.info("#{__MODULE__}: Failed to add synced block #{block_height}: #{reason}")
        {:error, peer_id, block_height}
    end
  end

  ## Ping logic makes sure they always agree on genesis header (height 0)
  ## We look for the block that is both on remote highest chain and in our local
  ## chain, connected to genesis (may be on a fork, but that fork
  ## has now more difficulty than our highest chain (otherwise we would not sync))
  ## agreed_hash is hash at height min (genesis hash)
  defp agree_on_height(_peer_id, _r_header_hash, _rheight, _lheight, min, min, agreed_header_hash) do
    {:ok, min, agreed_header_hash}
  end

  defp agree_on_height(
         peer_id,
         remote_header_hash,
         remote_height,
         local_height,
         max_agreed_height,
         min_agreed_height,
         agreed_header_hash
       )
       when remote_height == local_height do
    case Chainstate.get_block(remote_header_hash) do
      {:ok, _} ->
        ## We agree on block
        middle_height = div(max_agreed_height + remote_height, 2)

        case min_agreed_height < middle_height and middle_height < max_agreed_height do
          true ->
            agree_on_height(
              peer_id,
              remote_header_hash,
              remote_height,
              middle_height,
              max_agreed_height,
              remote_height,
              remote_header_hash
            )

          false ->
            {:ok, remote_height, remote_header_hash}
        end

      _ ->
        ## We disagree. Local on a fork compared to remote, check half-way
        middle_height = div(min_agreed_height + remote_height, 2)

        if min_agreed_height < middle_height and middle_height < max_agreed_height do
          agree_on_height(
            peer_id,
            remote_header_hash,
            remote_height,
            middle_height,
            remote_height,
            min_agreed_height,
            agreed_header_hash
          )
        else
          {:ok, min_agreed_height, agreed_header_hash}
        end
    end
  end

  defp agree_on_height(
         peer_id,
         remote_header_hash,
         remote_height,
         local_height,
         max_agreed_height,
         min_agreed_height,
         agreed_header_hash
       )
       when remote_height != local_height do
    case PeerConnection.get_header_by_height(peer_id, local_height, remote_header_hash) do
      {:ok, %{header: header}} ->
        Logger.info(
          "#{__MODULE__}: New header received from #{inspect(peer_id)}: #{inspect(header)}"
        )

        new_remote_header_hash = Header.hash(header)

        agree_on_height(
          peer_id,
          new_remote_header_hash,
          local_height,
          local_height,
          max_agreed_height,
          min_agreed_height,
          agreed_header_hash
        )

      {:error, reason} ->
        Logger.info(
          "#{__MODULE__}: Fetching header #{local_height} from #{inspect(peer_id)} failed: #{
            reason
          }"
        )

        {:error, reason}
    end
  end

  defp fill_pool(peer_id, start_header_hash, target_header_hash, task_id) do
    case PeerConnection.get_n_successors(
           start_header_hash,
           target_header_hash,
           @max_headers_per_chunk,
           peer_id
         ) do
      {:ok, %{hashes: []}} ->
        Logger.info("#{__MODULE__}: Sync done (according to #{inspect(peer_id)})")
        update_sync_task({:done, peer_id}, task_id)

      {:ok, %{hashes: hashes}} ->
        hash_pool = Enum.map(hashes, fn {height, header_hash} -> {height, header_hash, false} end)
        Logger.info("#{__MODULE__}: Filling pool with hashes from #{inspect(peer_id)}")
        work_on_sync_task(peer_id, task_id, {:hash_pool, hash_pool})

      {:error, _} = err ->
        Logger.info("#{__MODULE__}: Abort sync with #{inspect(peer_id)} for #{err}")
        update_sync_task({:error, peer_id}, task_id)
        {:error, :sync_abort}
    end
  end

  # Check if we already have this block locally, is so
  # take it from the chain
  defp fetch_block(header_hash, peer_pid) do
    case Chainstate.get_block(header_hash) do
      {:ok, block} ->
        Logger.debug(fn -> "#{__MODULE__}: We already have this block!" end)
        {:ok, false, block}

      {:error, _} ->
        fetch_block_ext(header_hash, peer_pid)
    end
  end

  # If we don't have the block locally, take it from the Remote Peer
  defp fetch_block_ext(header_hash, peer_pid) do
    case PeerConnection.get_block(header_hash, peer_pid) do
      {:ok, %{block: block}} ->
        case Header.hash(block.header) === header_hash do
          true ->
            Logger.debug(fn ->
              "#{__MODULE__}: Block #{inspect(block)} fetched from #{inspect(peer_pid)}"
            end)

            {:ok, true, block}

          false ->
            Logger.error(fn ->
              "#{__MODULE__}: Calculated header for block #{inspect(block)} does not match header hash: #{
                header_hash
              }"
            end)

            {:error, :header_hash_mismatch}
        end

      err ->
        Logger.debug(fn ->
          "#{__MODULE__}: Failed to fetch the block from #{inspect(peer_pid)}"
        end)

        err
    end
  end

  ## Checks if peer is syncing
  defp peer_in_sync?(%Sync{sync_tasks: tasks}, peer_id) do
    tasks
    |> Enum.map(fn %Task{chain: %Chain{peers: peers}} -> peers end)
    |> Enum.member?(peer_id)
  end
end
