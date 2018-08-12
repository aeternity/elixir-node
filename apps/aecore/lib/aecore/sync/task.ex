defmodule Aecore.Sync.Task do

  alias Aecore.Sync.Chain
  
   defstruct id: nil,
    chain: nil,
    pool: [],
    agreed: nil,
    adding: [],
    pending: [],
    workers: []

  use ExConstructor

  @type sync_task :: %Task{}
  @type sync_tasks :: list(%Task{})
  
  def get_sync_task(stid, %Sync{sync_tasks: sts}) do
    case Enum.find(sts, fn %{id: id} -> id == stid) do
      nil -> {:error, :not_found}
      st -> {:ok, st}
    end
  end

  def set_sync_task(%Task{} = st, %Sync{sync_tasks: sts}) do
    %Sync{sync_tasks: keystore(sts, st)}
  end

  def delete_sync_task(%Task{id: stid}, %Sync{sync_tasks: sts}) do
    %Sync{sync_tasks: Enum.filter(sts, fn %{id: id} -> id != stid end)}
  end

  def do_update_sync_task(state, stid, update) do
    case get_sync_task(stid, state) do
      {:ok, %Task{chain: %Chain{peers: peers}} = st} ->
        chain1 =
          case update do
            {:done, peer_id} -> %Chain{peers: peers -- [peer_id]}
            {:error, peer_id} -> %Chain{peers: peers -- [peer_id]}
          end
        maybe_end_sync_task(state, %Task{chain: chain1})

      {:error, :not_found} ->
        ## Sync Task not found
        state
    end
  end

  def maybe_end_sync_task(state, %Task{chain: chain} = st) do
    case chain do
      %{peers: [], chain: [target | []]} ->
        ## Removing/ending SyncTask: st with target: target
        delete_sync_task(st, state)

      _ ->
        set_sync_task(st, state)
    end
  end
  
  def match_task(_chain, [], []), do: :no_match

  def match_task(chain, [], acc) do
    {n, %Chain{chain_id: cid, peers: peers}} = hd(Enum.reverse(acc))
    {:inconclusive, chain, {:get_header, cid, peers, n}}
  end

  def match_task(chain1, [%Task{chain: chain2} | sts], acc) do
    case Chain.match_chains(Map.get(chain1, :chain), Map.get(chain2, :chain)) do
      :equal -> {:match, st}
      :different -> match_tasks(chain1, sts, acc)
      {:first, n} -> match_tasks(chain1, sts, [{n, chain1} | acc])
      {:second, n} -> match_tasks(chain1, sts, [{n, chain2} | acc])
    end
  end

  @doc """
  Gets a list of tasks and a singe task. If an id of a task inside
  the list of tasks is equal to the id of the given task,
  change the tasks. Otherwise add the given task to the end of list of tasks
  """
  @spec keystore(sync_tasks(), sync_task()) :: sync_tasks()
  def keystore(sts, %Task{} = st) do
    do_keystore(sts, st, [])
  end

  defp do_keystore([%Task{id: id} | sts], %Task{id: id} = st, acc) do
    acc ++ [st] ++ tail
  end

  defp do_keystore([head | sts], st, acc) do
    keystore(sts, st, [head | acc])
  end

  defp do_keystore([], st, acc) do
    acc ++ [st]
  end
end
