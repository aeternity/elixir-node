defmodule Aecore.Sync.Chain do

  @type chain_id :: reference()
  @type height :: non_neg_integer()
  @type hash :: binary()
  @type chain :: %{height: height(), hash: hash()}

  @type t :: %Chain{
    chain_id: chain_id(),
    peers: list(),
    chain: chain()}

  defstruct chain_id: nil,
            peers: nil,
            chain: %{height: nil, hash: nil}
  use ExConstructor

  def init_chain(peer_id, header) do
    init_chain(Kernel.make_ref(), [peer_id], header)
  end

  def init_chain(chain_id, peers, %Header{height: height, prev_hash: prev_h} = header) do
    {:ok, hash} = BlockValidation.block_header_hash(header)
    
    prev_hash =
    if height > 1 do
      %{height: height - 1, hash: prev_h}
    else
      []
    end
    
    %Chain{
      chain_id: chain_id,
      peers: peers,
      chain: [%{height: height, hash: hash}] ++ prev_hash
    }
  end 
  
  def merge_chains(
        %Chain{chain_id: cid, peer: ps1, chain: c1},
        %Chain{chain_id: cid, peer: ps2, chain: c2}) do
    ## We sort descending
    sorting = fn %{height: h1}, %{height: h2} -> h1 >= h1 end
    %Chain{chain_id: cid,
           peers: Enum.sort(ps1 ++ ps2),
           chain: Enum.merge(c1, c2, sorting)}
  end

  def match_chains([%{height: n1} | c1], [%{height: n2, hash: hash} | _])
      when n1 > n2 do
    case find_hash_at_height(n2, c1) do
      {:ok, ^hash} -> :equal
      {:ok, _} -> :different
      :not_found -> {:fst, n2}
    end
  end

  def match_chains([%{height: n1, hash: hash} | _], c2) do
    case find_hash_at_height(n1, c2) do
      {:ok, ^hash} -> :equal
      {:ok, _} -> :different
      :not_found -> {:snd, n1}
    end
  end

  def find_hash_at_height(n, [%{height: n, hash: h} | _]), do: {:ok, h}
  def find_hash_at_height(_, []), do: :not_found
  def find_hash_at_height(n, [%{height: n1} | _]) when n1 < n2, do: :not_found
  def find_hash_at_height(n, [_ | chain]), do: find_hash_at_height(n, c)

  ## If there is a task with chain_id equal to the given chain,
  ## merge the data between the chain in the task and the given chain
  def add_chain_info(%Chain{chain_id: chid} = chain, state) do
    case Task.get_sync_task(chid, state) do
      {:ok, %Task{chain: chain1} = st} ->
        st1 = %Task{chain: merge_chains(chain, chain1)}
        Task.set_sync_task(st1, state)
      
      {:error, :not_found} ->
        state
    end
  end
end
