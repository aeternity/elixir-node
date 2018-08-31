defmodule Aecore.Sync.Chain do
  @moduledoc """
  Implements all the functions regarding the Chain structure of the SyncTask
  """

  alias Aecore.Chain.Header
  alias Aecore.Chain.BlockValidation
  alias Aecore.Sync.Task
  alias Aeutil.List, as: ListUtils
  alias __MODULE__

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
    header_hash = BlockValidation.block_header_hash(header)

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

    %Chain{chain_id: chain_id, peers: peers, chain: ListUtils.merge_descending(chain_1, chain_2)}
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
end
