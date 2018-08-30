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

  @typespec "Id specifing the chain to which we are syncing"
  @type chain_id :: reference()

  @typespec "Id of the peer we are communicating with"
  @type peer_id :: pid()

  @typespec "List of all the sync tasks we are currently syncing against"
  @type sync_tasks :: list(%Task{})

  @typespec "Id of the current task"
  @type task_id :: reference()

  @typespec "Element holding weather we have this block or not, 
  and if we don't from where could we take it (local/remote peer)"
  @type pool_elem :: {height(), hash(), {peer_id(), Block.t()} | {:ok, :local} | false}

  @typespec "On what header data (height + hash) do we agree upon when starting a sync task"
  @type agreed :: %{height: height(), hash: hash()} | nil

  @typespec "Process resolving syncing implemetation with a specific peer"
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

  @spec init_sync_task(Chain.t()) :: t()
  def init_sync_task(%Chain{chain_id: id} = chain) do
    %Task{id: id, chain: chain}
  end

  @spec get_sync_task(task_id(), Sync.t()) :: {:ok, t()} | {:error, :not_found}
  def get_sync_task(task_id, %Sync{sync_tasks: tasks}) do
    case Enum.find(tasks, fn %{id: id} -> id == task_id end) do
      nil -> {:error, :not_found}
      task -> {:ok, task}
    end
  end

  @spec set_sync_task(t(), Sync.t()) :: Sync.t()
  def set_sync_task(%Task{id: id} = task, %Sync{sync_tasks: tasks} = sync) do
    %Sync{sync | sync_tasks: keystore(id, task, tasks)}
  end

  @spec set_sync_task(task_id(), t(), Sync.t()) :: Sync.t()
  def set_sync_task(id, %Task{} = task, %Sync{sync_tasks: tasks} = sync) do
    %Sync{sync | sync_tasks: keystore(id, task, tasks)}
  end

  @spec delete_sync_task(t(), Sync.t()) :: Sync.t()
  def delete_sync_task(%Task{id: task_id}, %Sync{sync_tasks: tasks} = sync) do
    %Sync{sync | sync_tasks: Enum.filter(tasks, fn %{id: id} -> id != task_id end)}
  end

  @spec do_update_sync_task(Sync.t(), task_id(), {:done | :error, peer_id()}) :: Sync.t()
  def do_update_sync_task(sync, task_id, update) do
    case get_sync_task(task_id, sync) do
      {:ok, %Task{chain: %Chain{peers: peers} = chain} = task} ->
        chain1 =
          case update do
            {:done, peer_id} -> %Chain{chain | peers: peers -- [peer_id]}
            {:error, peer_id} -> %Chain{chain | peers: peers -- [peer_id]}
          end

        maybe_end_sync_task(sync, %{task | chain: chain1})

      {:error, :not_found} ->
        Logger.info("#{__MODULE__}: Sync task not found!")
        sync
    end
  end

  @spec maybe_end_sync_task(Sync.t(), t()) :: Sync.t()
  def maybe_end_sync_task(sync, %Task{chain: chain} = task) do
    case chain do
      %Chain{peers: [], chain: [target | _]} ->
        Logger.info("#{__MODULE__}: Removing Sync task: task with target: #{inspect(target)}")
        delete_sync_task(task, sync)

      _ ->
        set_sync_task(task, sync)
    end
  end

  @spec match_tasks(Chain.t(), Sync.t(), list()) ::
          :no_match
          | {:inconclusive, Chain.t(), {:get_header, chain_id(), peer_id(), height()}}
          | {:match, t()}
  def match_tasks(_chain, [], []), do: :no_match

  def match_tasks(chain, [], acc) do
    {height, %Chain{chain_id: cid, peers: peers}} = hd(Enum.reverse(acc))
    {:inconclusive, chain, {:get_header, cid, peers, height}}
  end

  def match_tasks(chain_1, [%Task{chain: chain_2} = task | tasks], acc) do
    case Chain.match_chains(Map.get(chain_1, :chain), Map.get(chain_2, :chain)) do
      :equal -> {:match, task}
      :different -> match_tasks(chain_1, tasks, acc)
      {:first, height} -> match_tasks(chain_1, tasks, [{height, chain_1} | acc])
      {:second, height} -> match_tasks(chain_1, tasks, [{height, chain_2} | acc])
    end
  end

  @doc """
  This function gets a list of arguments and a single element. If this element
  is present in the list -> update the list with it's values.
  If not -> add the element to the list
  """
  @spec keystore(peer_id() | task_id(), t() | worker(), t() | list(worker())) ::
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
