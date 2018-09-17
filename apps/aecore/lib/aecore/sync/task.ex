defmodule Aecore.Sync.Task do
  @moduledoc """
  Each sync task holds information about a syncing process with multiple peers 
  where each peer is recognized as a worker with peer_id and pid of a seperate process doing the work.
  A sync task works on a specific chain, meaning there is one sync task per chain.
  If a worker is on different chain (on a fork, meaning different chain than what we already syncing against)
  a new sync task will be started. In the normal case where all is good 
  all peers work on the same task, we work only on one sync task.
  """

  alias Aecore.Sync.Chain
  alias Aecore.Sync.Sync
  alias Aecore.Chain.Block
  alias __MODULE__

  require Logger

  @type height :: non_neg_integer()
  @type hash :: binary()

  @typedoc "Id specifing the chain to which we are syncing"
  @type chain_id :: reference()

  @typedoc "Id of the peer we are communicating with"
  @type peer_id :: pid()

  @typedoc "List of all the sync tasks we are currently syncing against"
  @type sync_tasks :: list(%Task{})

  @typedoc "Id of the current task"
  @type task_id :: reference()

  @typedoc "Element holding weather we have this block or not,
  and if we don't from where could we take it (local/remote peer)"
  @type pool_elem :: {height(), hash(), {peer_id(), Block.t()} | {:ok, :local} | false}

  @typedoc "On what header data (height + hash) do we agree upon when starting a sync task"
  @type agreed :: %{height: height(), hash: hash()} | nil

  @typedoc "Process resolving syncing implemetation with a specific peer"
  @type worker :: {peer_id(), pid()}

  @type t :: %Task{
          id: task_id(),
          chain: Chain.t(),
          pool: list(pool_elem()),
          agreed: agreed(),
          adding: list(pool_elem()),
          pending: list(pool_elem()),
          workers: list(worker())
        }

  defstruct id: nil,
            chain: nil,
            pool: [],
            agreed: nil,
            adding: [],
            pending: [],
            workers: []

  @spec init_sync_task(Chain.t()) :: Task.t()
  def init_sync_task(%Chain{chain_id: id} = chain) do
    %Task{id: id, chain: chain}
  end

  @spec get_sync_task(task_id(), Sync.t()) :: {:ok, Task.t()} | {:error, :not_found}
  def get_sync_task(task_id, %Sync{sync_tasks: tasks}) do
    case Enum.find(tasks, fn %{id: id} -> id == task_id end) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  @spec set_sync_task(Task.t(), Sync.t()) :: Sync.t()
  def set_sync_task(%Task{id: id} = task, %Sync{sync_tasks: tasks} = sync) do
    %Sync{sync | sync_tasks: keystore(id, task, tasks)}
  end

  @spec set_sync_task(task_id(), Task.t(), Sync.t()) :: Sync.t()
  def set_sync_task(id, %Task{} = task, %Sync{sync_tasks: tasks} = sync) do
    %Sync{sync | sync_tasks: keystore(id, task, tasks)}
  end

  @spec delete_sync_task(Task.t(), Sync.t()) :: Sync.t()
  def delete_sync_task(%Task{id: task_id}, %Sync{sync_tasks: tasks} = sync) do
    %Sync{sync | sync_tasks: Enum.filter(tasks, fn %{id: id} -> id != task_id end)}
  end

  @spec do_update_sync_task(Sync.t(), task_id(), {:done | :error, peer_id()}) :: Sync.t()
  def do_update_sync_task(sync, task_id, update) do
    case get_sync_task(task_id, sync) do
      {:ok, %Task{chain: %Chain{peers: peers} = task_chain} = task} ->
        chain_with_removed_peer_id =
          case update do
            {:done, peer_id} -> %Chain{task_chain | peers: peers -- [peer_id]}
            {:error, peer_id} -> %Chain{task_chain | peers: peers -- [peer_id]}
          end

        maybe_end_sync_task(sync, %Task{task | chain: chain_with_removed_peer_id})

      {:error, :not_found} ->
        Logger.info("#{__MODULE__}: Sync task not found!")
        sync
    end
  end

  @spec maybe_end_sync_task(Sync.t(), Task.t()) :: Sync.t()
  def maybe_end_sync_task(sync, %Task{chain: chain} = task) do
    case chain do
      %Chain{peers: [], chain: [target_chain | _]} ->
        Logger.info(
          "#{__MODULE__}: Removing Sync task: task with target: #{inspect(target_chain)}"
        )

        delete_sync_task(task, sync)

      _ ->
        set_sync_task(task, sync)
    end
  end

  @spec match_chain_to_task(Chain.t(), Sync.t(), list()) ::
          :no_match
          | {:inconclusive, Chain.t(), {:get_header, chain_id(), peer_id(), height()}}
          | {:match, Task.t()}
  def match_chain_to_task(_incoming_chain, [], []), do: :no_match

  def match_chain_to_task(incoming_chain, [], acc) do
    {height, %Chain{chain_id: cid, peers: peers}} = hd(Enum.reverse(acc))
    {:inconclusive, incoming_chain, {:get_header, cid, peers, height}}
  end

  def match_chain_to_task(incoming_chain, [%Task{chain: task_chain} = task | tasks], acc) do
    case Chain.try_match_chains(Map.get(incoming_chain, :chain), Map.get(task_chain, :chain)) do
      :equal ->
        {:match, task}

      :different ->
        match_chain_to_task(incoming_chain, tasks, acc)

      {:first, height} ->
        match_chain_to_task(incoming_chain, tasks, [{height, incoming_chain} | acc])

      {:second, height} ->
        match_chain_to_task(incoming_chain, tasks, [{height, task_chain} | acc])
    end
  end

  @doc """
  This function gets a list of arguments and a single element. If this element
  is present in the list -> update the list with it's values.
  If not -> add the element to the list
  """
  @spec keystore(peer_id() | task_id(), Task.t() | worker(), Task.t() | list(worker())) ::
          sync_tasks() | list(worker())
  def keystore(id, elem, elems) do
    do_keystore(elems, elem, id, [])
  end

  defp do_keystore([{id, _} | elems], elem, id, acc) do
    acc ++ [elem] ++ elems
  end

  defp do_keystore([%{id: id} | elems], elem, id, acc) do
    acc ++ [elem] ++ elems
  end

  defp do_keystore([head | elems], elem, id, acc) do
    do_keystore(elems, elem, id, [head | acc])
  end

  defp do_keystore([], elem, _id, acc) do
    Enum.reverse([elem | Enum.reverse(acc)])
  end
end
