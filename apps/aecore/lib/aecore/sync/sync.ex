defmodule Aecore.Sync.Sync do

  use GenServer

  alias Aecore.Sync.{Jobs, Chain, Task}

  ###===================================================
  ### API calls
  ###===================================================
  
  def start_sync(peer_id, remote_hash, remote_difficulty) do
    GenServer.cast(__MODULE__, {:start_sync, peer_id, remote_hash, remote_difficulty})
  end

  def schedule_ping(peer_id) do
    GenServer.case(__MODULE__, {:schedule_ping, peer_id})
  end

  def sync_in_progress?(peer_id) do
    GenServer.call(__MODULE__, {:sync_in_progress, peer_id})
  end

  def known_chain(chain, extra_info) do
    GenServer.call(__MODULE__, {:known_chain, chain, extra_info})
  end

  def update_sync_task(update, task) do
    GenServer.call(__MODULE__, {:update_sync_task, update, task})
  end

  def next_work_item(task, peer_id, last_result) do
    GenServer.call(__MODULE__, {:next_work_item, task, peer_id, last_result})
  end

  def handle_worker(task, action) do
    GenServer.cast(__MODULE__, {:handle_worker, task, action})
  end

  ###==================================================================
  ### GenServer functions
  ###==================================================================

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{sync_tasks: []}, name: __MODULE__)
  end
  
  def init(state) do
    Jobs.init_jobs()
    {:ok, state}
  end

  def handle_call({:sync_in_progress, peer_id}, _from, state) do
    {:reply, peer_in_sync(state, peer_id), state}
  end

  def handle_call({:known_chain, %{chain_id: cid}}, _from, state) do
    ## Do some work
    ##{:reply, res, new_state}
  end

  def handle_call({:update_sync_task, update, st_id}, _from, state) do
    new_state = do_update_sync_task(state, st_id, update)
    {:reply, :ok, new_state}
  end

  def handle_call({:next_work_item, st_id, peer_id, {:error, reason}}, _from, state) do
    new_state = do_update_sync_task(state, st_id, {:error, peer_id})
    {:reply, :abort_work, new_state)
  end

  def handle_call({:next_work_item, st_id, peer_id, last_result}, _from, state) do
    state1 = handle_last_result(state, st_id, last_result)
    {reply, state2} = get_next_work_item(state1, st_id, peer_id)
    {:reply, reply, state2}
  end

  ## Handle casts

  def handle_cast({:start_sync, peer_id, remote_hash, _remote_diff}, state) do
    Jobs.run_job(:sync_task_workers, fn -> do_start_sync(peer_id, remote_hash end))
    {:noreply, state}
  end

  def handle_cast({:schedule_ping, peer_id}, state) do
    if peer_in_sync(state, peer_id) do
      :ok
    else
      Jobs.run(:sync_ping_workers, fn -> ping_peer(peer_id) end)
    end
  end

  def handle_cast({:handle_worker, st_id, action}, state) do
    state1 =
      case get_sync_task(st_id, state) do
        {:ok, sync_task} ->
          sync_task1 = do_handle_worker(action, sync_task)
          set_sync_task(sync_task1, state)

        {:error, :not_found} ->
          state
      end
    {:noreply, state1)
  end

  def handle_cast(_, state), do: {:noreply, state)

  def handle_info({:gproc_ps_event, event, %{info: info}}, state) do
    peer_ids = Enum.map(Peers.get_random(:all), fn pid -> Peers.peer_id(pid) end)
    non_syncing_peer_ids = Enum.filter(peer_ids, fn pid -> not peer_in_sync(state, pid) end)
    case event do
      :new_top_block -> Jobs.enqueue(:block, info, non_syncing_peer_ids)
      :tx_created -> Jobs.enqueue(:tx, info, peer_ids)
      :tx_received -> Jobs.enqueue(:tx, info, peer_ids)
      _ -> :ignore
    end
  end

  def sync_task_for_chain(chain, %{sync_tasks: sts} = state) do
    case match_tasks(chain, sts, []) do
      :no_match ->
        st = init_sync_task(chain)
        {{:new, chain, st.id}, set_sync_task(st, state)}
      
      {:match, %Task{id: st_id, chain: chain2} = st} ->
        new_chain = merge_chains(%Chain{chain_id: st_id}, chain2)
        st1 = %Task{st | chain: new_chain}
        {{:existing, stid}, set_sync_task(st1, state)}

      {:inconclusive, _, _} = res ->
        {res, state}
    end
  end

  def handle_last_result(state, stid, last_result) do
    case Task.get_sync_task(stid, state) do
      {:ok, st} ->
        st1 = handle_last_result(st, last_result)
        maybe_end_sync_task(state, st1)
      
      {:error, :not_found} ->
        state
    end
  end

  def handle_last_result(st, :none), do: st
  
  def handle_last_result(%Task{agreed: :undefined} = st, {:agreed_height, agreed}), do: %Task{st | agreed: agreed}

  def handle_last_result(%Task{pool: []} = st, {:hash_pool, hash_pool}) do
    {height, hash, false} = List.last(hash_pool)
    %Task{st | pool: hash_pool, agreed: %{height: height, hash: hash}}
  end

  def handle_last_result(%Task{} = st, {:hash_pool, _hash_pool}), do: st

  def handle_last_result(
        %Task{pool: pool} = st,
        {:get_block, height, hash, peer_id, {:ok, block}}) do
    pool1 =
      Enum.map(pool, fn
        {^height, _, _} -> {height, hash, {peer_id, block}}
        elem -> elem
      end)
    %Task{st | pool: pool1}
  end

  def handle_last_result(%Task{} = st, {:post_blocks, :ok}), do: %Task{st | adding: []}

  def handle_last_result(
        %Task{adding: adds, pending: pends, pool: pool, chain: chain},
        {:post_blocks, {:error, block_from_peer_id, height}}) do
    ## Put back the blocks we did not manage to post, and schedule
    ## failing block for another retraival
    [{height, hash, _} | put_back] =
      Enum.filter(adds, fn {h, _, _} -> h < height end) ++ pends

    new_pool = [{height, hash, false} | put_back] ++ pool

    %Task{st |
          adding: [],
          pending: [],
          pool: new_pool,
          chain: %Chain{chain | peers: chain.peers -- [blocked_from_peer_id]}}
  end

  def split_pool(pool), do: split_pool(pool, [])

  def split_pool([{_, _, false} | _] = pool, acc), do: {List.reverse(acc), pool}

  def split_pool([], acc), do: {List.reverse(acc), []}

  def split_pool([p | pool], acc) -> split_pool(pool, [p | acc])

  def get_next_work_item(state, stid, peer_id) do
    with
    {:ok, %Task{chain: %Chain{peers: peer_ids}}} <- Task.get_sync_task(stid, state),
      true <- Enum.member?(peer_ids, peer_id) do
      {action, st1} = get_next_work_item(st)
      {action, Task.set_sync_task(stid, st1, state)}
    else
      _ ->
      {:abort_work, state}
    end
  end

  def get_next_work_item(%Task{adding: [], pending: [to_add | new_pending]} = st) do
    {{:post_blocks, to_add}, %Task{st | adding: to_add, pending: new_pending}}
  end

  def get_next_work_item(%Task{chain: chain, agreed: :undefined} = st) do
    {{:agree_on_height, chain}, st}
  end

  def get_next_work_item(%Task{pool: [], agreed: %{height: height, hash: last_hash}, chain: %Chain{chain: chain}}) do
    target_hash = next_known_hash(chain, height + @max_headers_per_chunk)
    {{:fill_pool, last_hash, target_hash}, st}
  end

  def get_next_work_item(%Task{pool: [{_, _, {_, _}} | _] = pool, adding: add, pending: pend} = st) do
    {to_be_added, new_pool} = split_pool(pool)
    case add do
      [] ->
        {{:post_blocks, to_be_added}, %Task{st | pool: new_pool, adding: to_be_added}}

      _ when length(pend) < 10 || new_pool != [] ->
        get_next_work_item(%Task{st | pool: new_pool, pending: pend ++ [to_be_added]})

      _ ->
        {:take_a_break, st}
    end
  end

  def get_next_work_item(%Task{pool: [{_, _, false} | _] = pool} = st) do
    pick_from = Enum.filter(pool, fn {_, _, elem} -> elem == false end)
    random = :rand.uniform(length(pick_from))
    {pick_height, pick_hash, false} = Enum.at(pick_from, random)

    ## Get block at height: pick_height
    {{:get_block, pick_height, pick_hash}, st}
  end

  def get_next_work_item(%Task{} = st) do
    ## Nothing to do
    {:take_a_break, st}
  end

  def do_handle_worker({:new_worker, peer_id, pid}, %Task{workers: ws} = st) do
    case Enum.filter(ws, fn {p_id, _} -> p_id == peer_id end) do
      [] -> :ok
      [{_, old}] -> :unfinished ## Peer already has worker
    end
    ## :erlang.link(pid)
    %Task{st | workers: :unfinished} ## :list.keystore(...)
  end

  def do_handle_worker({:change_worker, peer_id, old_pid, new_pid}, %Task{workers: ws} = st) do
    case Enum.filter(ws, fn {p_id, _} -> p_id == peer_id end) do
      [] -> :unfinished ## Log info
      [{_, old_pid}] -> :ok
      [{_, another_pid}] -> :unfinished ## Log info
    end

    ## :erlang.link(new_pid)
    ## :erlang.unlink(old_pid)
    ## Log info

    %Task{st | workers: :unfinished} ## :list.keystore(...)
  end

  def do_terminate_worker(pid, %Sync{sync_tasks: sts} = state) do
    case Enum.filter(sts, fn %{workers: {_, p}} -> p == pid end) do
      [st] ->
        pid
        |> do_terminate_worker(st)
        |> Task.set_sync_task(state)
      
      [] ->
        state
    end
  end

  def do_terminate_worker(pid, %Task{workers: ws} = st) do
    [{peer, _}] = Enum.filter(ws, fn {_, p} -> p == pid end)
    ## Log info
    %Task{st | workers: Enum.filter(ws, fn {_, p} -> p != pid end)}
  end

  def ping_peer(peer_id) do
    res = PeerConnection.ping(peer_id)
    ## Log res
    case res do
      :ok -> :unfinished ## Log ping
      {:error, _} -> :unfinished ## Log ping
    end
  end

  def do_forward_block(block, peer_id) do
    res = PeerConnection.send_block(peer_id, block)
    ## Log res
  end

  def do_forward_tx(tx, peer_id) do
    res = PeerConnection.send_tx(peer_id, tx)
    ## Log res
  end

  def do_start_sync(peer_id, remote_hash) do
    if sync_in_progress?(peer_id) do
      :unfinished ## Log - Already syncing
    else
      do_start_sync1(peer_id, remote_hash)
    end
  end

  def do_start_sync1(peerd_id, remote_hash) do
    case PeerConnection.get_header_by_height(peer_id, remote_hash) do
      {:ok, header} ->
        ## Log -> New header received

        ## We do try really hard to identify the same chain here...
        chain = init_chain(peer_id, header)
        case known_chain(chain) do
          {:ok, task} ->
            :unfinished ## Examine the self() part here
            handle_worker(task, {:new_worker, peer_id, self()})
            do_work_on_sync_task(peer_id, task)

          {:error, reason} ->
            ## Log -> Could not identify chain, aborting sync
            :unfinished
        end

      {:error, reason} ->
        ## Log -> fetching top block failed
        :unfinished
    end
  end

  def known_chain(chain) do
    chain
    |> known_chain(:none)
    |> idenify_chain()
  end

  def identify_chain({:existing, task}) do
    ## Log info -> Already syncing chain
    {:ok, task}
  end
  
  def identify_chain({:new, %Chain{chain: [target | _]}, task}) do
    ## Log info -> Started new sync task with target
    {:ok, task}
  end

  def identify_chain({:inconclusive, chain, {:get_eader, ch_id, peers, n}}) do
    ## We need another hash for this chain, make sure whoever we ask
    ## is still in this particular chain by including a known (at higher height) hash
    known_hash = Chain.next_known_hash(chain.chain, n)
    case do_get_header_by_height(peers, n, known_hash) do
      {:ok, header} ->
        chain
        |> known_chain(Chain.init_chain(ch_id, peers, header))
        |> identify_chain()

      {:error, _} = err ->
        ## Log info -> Fetching header at height: h from: peers failed
        err
    end
  end

  ## Get the next known hash at a height bigger than N; or
  ## if no such hash exist, the hash at the highest known height.
  def next_known_chain(cs, n) do
    ## TODO: finish this function
  end



























  
end
