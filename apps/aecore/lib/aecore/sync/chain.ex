defmodule Aecore.Sync.Chain do
  @moduledoc """
  Implements all the functions regarding the Chain structure of the SyncTask
  """

  alias Aecore.Chain.Header
  alias Aecore.Chain.BlockValidation
  alias Aecore.Sync.Task
  alias __MODULE__

  @type peer_id :: pid()
  @type chain_id :: reference()
  @type height :: non_neg_integer()
  @type hash :: binary()
  @type chain :: %{height: height(), hash: hash()}

  @type t :: %Chain{chain_id: chain_id(), peers: list(), chain: list(chain())}

  defstruct chain_id: nil,
            peers: [],
            chain: []

  @spec init_chain(peer_id(), Header.t()) :: t()
  def init_chain(peer_id, header) do
    init_chain(Kernel.make_ref(), [peer_id], header)
  end

  @spec init_chain(chain_id(), peer_id(), Header.t()) :: t()
  def init_chain(chain_id, peers, %Header{height: height, prev_hash: prev_hash} = header) do
    hash = BlockValidation.block_header_hash(header)

    prev_header_data =
      if height > 1 do
        [%{height: height - 1, hash: prev_hash}]
      else
        []
      end

    %Chain{
      chain_id: chain_id,
      peers: peers,
      chain: [%{height: height, hash: hash}] ++ prev_header_data
    }
  end

  @spec merge_chains(t(), t()) :: t()
  def merge_chains(%Chain{chain_id: chain_id, peers: peers_1, chain: chain_1}, %Chain{
        chain_id: chain_id,
        peers: peers_2,
        chain: chain_2
      }) do
    peers =
      (peers_1 ++ peers_2)
      |> Enum.sort()
      |> Enum.uniq()

    %Chain{chain_id: chain_id, peers: peers, chain: merge(chain_1, chain_2)}
  end

  @spec match_chains(list(chain()), list(chain())) ::
          :equal | :different | {:first | :second, height()}
  def match_chains([%{height: height_1} | chain_1], [%{height: height_2, hash: hash} | _])
      when height_1 > height_2 do
    case find_hash_at_height(height_2, chain_1) do
      {:ok, ^hash} -> :equal
      {:ok, _} -> :different
      :not_found -> {:first, height_2}
    end
  end

  def match_chains([%{height: height_1, hash: hash} | _], chain_2) do
    case find_hash_at_height(height_1, chain_2) do
      {:ok, ^hash} -> :equal
      {:ok, _} -> :different
      :not_found -> {:second, height_1}
    end
  end

  @spec find_hash_at_height(height(), list(chain())) :: {:ok, hash()} | :not_found
  def find_hash_at_height(height, [%{height: height, hash: hash} | _]), do: {:ok, hash}
  def find_hash_at_height(_, []), do: :not_found

  def find_hash_at_height(height, [%{height: height_1} | _]) when height_1 < height,
    do: :not_found

  def find_hash_at_height(height, [_ | chain]), do: find_hash_at_height(height, chain)

  @doc """
  If there is a task with chain_id equal to the given chain,
  merge the data between the chain in the task and the given chain
  """
  @spec add_chain_info(t(), Sync.t()) :: Sync.t()
  def add_chain_info(%Chain{chain_id: chain_id} = chain, sync) do
    case Task.get_sync_task(chain_id, sync) do
      {:ok, st = %Task{chain: chain_1}} ->
        st1 = struct(st, chain: merge_chains(chain, chain_1))
        Task.set_sync_task(st1, sync)

      {:error, :not_found} ->
        sync
    end
  end

  @doc """
  Get the next known hash at a height bigger than N; or
  if no such hash exist, the hash at the highest known height.
  """
  @spec next_known_hash(t(), height()) :: hash()
  def next_known_hash(chains, height) do
    %{hash: hash} =
      case Enum.take_while(chains, fn %{height: h} -> h > height end) do
        [] -> Kernel.hd(chains)
        chains_1 -> List.last(chains_1)
      end

    hash
  end

  @doc """
  Merge two chains while keeping their descending order
  """
  @spec merge(t(), t()) :: t()
  def merge(chain_1, chain_2) do
    merge(chain_1, chain_2, [])
  end

  @spec merge(t(), t(), list()) :: t()
  defp merge([], [], acc) do
    acc
    |> Enum.sort()
    |> Enum.reverse()
  end

  defp merge([], [elem2 | chain_2], acc) do
    merge([], chain_2, [elem2 | acc])
  end

  defp merge([elem1 | chain_1], chain_2, acc) do
    case Enum.member?(chain_2, elem1) do
      true ->
        new_chain_2 = Enum.filter(chain_2, fn elem -> elem != elem1 end)
        merge(chain_1, new_chain_2, [elem1 | acc])

      false ->
        merge(chain_1, chain_2, [elem1 | acc])
    end
  end
end
