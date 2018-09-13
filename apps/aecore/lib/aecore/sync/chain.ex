defmodule Aecore.Sync.Chain do
  @moduledoc """
  Implements all the functions regarding the Chain structure of the SyncTask
  """
  alias __MODULE__
  alias Aecore.Chain.Header
  alias Aecore.Sync.Task

  @type peer_id :: pid()
  @type chain_id :: reference()
  @type height :: non_neg_integer()
  @type header_hash :: binary()

  @typedoc "Holds data for header height and hash"
  @type chain :: %{height: height(), hash: header_hash()}

  @type t :: %Chain{chain_id: chain_id(), peers: list(peer_id()), chain: list(chain())}

  defstruct chain_id: nil,
            peers: [],
            chain: []

  @spec init_chain(peer_id(), Header.t()) :: Chain.t()
  def init_chain(peer_id, header) do
    init_chain(Kernel.make_ref(), [peer_id], header)
  end

  @spec init_chain(chain_id(), peer_id(), Header.t()) :: Chain.t()
  def init_chain(chain_id, peers, %Header{height: height, prev_hash: prev_hash} = header) do
    header_hash = Header.hash(header)

    prev_header_data =
      if height > 1 do
        [%{height: height - 1, hash: prev_hash}]
      else
        []
      end

    %Chain{
      chain_id: chain_id,
      peers: peers,
      chain: [%{height: height, hash: header_hash}] ++ prev_header_data
    }
  end

  @spec merge_chains(Chain.t(), Chain.t()) :: Chain.t()
  def merge_chains(%Chain{chain_id: chain_id, peers: peers_1, chain: chain_1}, %Chain{
        chain_id: chain_id,
        peers: peers_2,
        chain: chain_2
      }) do
    peers =
      (peers_1 ++ peers_2)
      |> Enum.sort()
      |> Enum.uniq()

    %Chain{
      chain_id: chain_id,
      peers: peers,
      chain: merge_chain_list_descending(chain_1, chain_2)
    }
  end

  @spec try_match_chains(list(chain()), list(chain())) ::
          :equal | :different | {:first | :second, height()}
  def try_match_chains([%{height: height_1} | chain_1], [
        %{height: height_2, hash: header_hash} | _
      ])
      when height_1 > height_2 do
    case find_hash_at_height(height_2, chain_1) do
      {:ok, ^header_hash} -> :equal
      {:ok, _} -> :different
      :not_found -> {:first, height_2}
    end
  end

  def try_match_chains([%{height: height_1, hash: header_hash} | _], chain_2) do
    case find_hash_at_height(height_1, chain_2) do
      {:ok, ^header_hash} -> :equal
      {:ok, _} -> :different
      :not_found -> {:second, height_1}
    end
  end

  @spec find_hash_at_height(height(), list(chain())) :: {:ok, header_hash()} | :not_found
  def find_hash_at_height(height, [%{height: height, hash: header_hash} | _]),
    do: {:ok, header_hash}

  def find_hash_at_height(_, []), do: :not_found

  def find_hash_at_height(height, [%{height: height_1} | _]) when height_1 < height,
    do: :not_found

  def find_hash_at_height(height, [_ | chain]), do: find_hash_at_height(height, chain)

  @doc """
  If there is a task with chain_id equal to the given chain,
  merge the data between the chain in the task and the given chain
  """
  @spec add_chain_info(Chain.t(), Sync.t()) :: Sync.t()
  def add_chain_info(%Chain{chain_id: chain_id} = incoming_chain, sync) do
    case Task.get_sync_task(chain_id, sync) do
      {:ok, %Task{chain: current_chain} = task} ->
        merged_chain = merge_chains(incoming_chain, current_chain)
        task_with_merged_chain = %Task{task | chain: merged_chain}
        Task.set_sync_task(task_with_merged_chain, sync)

      {:error, :not_found} ->
        sync
    end
  end

  @doc """
  Get the next known header_hash at a height bigger than N; or
  if no such hash exist, the header_hash at the highest known height.
  """
  @spec next_known_header_hash(Chain.t(), height()) :: header_hash()
  def next_known_header_hash(chains, height) do
    %{hash: header_hash} =
      case Enum.take_while(chains, fn %{height: h} -> h > height end) do
        [] ->
          [chain | _] = chains
          chain

        chains_1 ->
          List.last(chains_1)
      end

    header_hash
  end

  ## Merges two list of chains, that are already sorted descending
  ## (based on the height), without keeping duplicates,
  ## where each element is a map with height and header hash
  defp merge_chain_list_descending(list1, list2) do
    merge(list1, list2, [])
  end

  defp merge([], [], acc), do: Enum.reverse(acc)

  defp merge([], [head2 | rest2], acc) do
    merge([], rest2, [head2 | acc])
  end

  defp merge([head1 | rest1], [], acc) do
    merge(rest1, [], [head1 | acc])
  end

  defp merge(
         [%{height: height1} = hd1 | rest1] = list1,
         [%{height: height2} = hd2 | rest2] = list2,
         acc
       ) do
    cond do
      height1 > height2 ->
        merge(rest1, list2, [hd1 | acc])

      height1 < height2 ->
        merge(list1, rest2, [hd2 | acc])

      true ->
        merge(rest1, rest2, [hd1 | acc])
    end
  end
end
