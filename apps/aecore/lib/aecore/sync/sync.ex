defmodule Aecore.Sync.SyncTest do

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
  
end
