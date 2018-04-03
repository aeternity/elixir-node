defmodule Aecore.Peers.Sync do
  @moduledoc """
  Contains peer sync functionality
  """

  use GenServer

  alias Aecore.Peers.Worker, as: Peers
  alias Aehttpclient.Client, as: HttpClient
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Structures.Header
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Chain.BlockValidation
  alias Aecore.Peers.PeerBlocksTask
  alias Aecore.Structures.Header

  require Logger

  @peers_target_count Application.get_env(:aecore, :peers)[:peers_target_count]

  def start_link(_args) do
    GenServer.start_link(
      __MODULE__,
      %{peer_blocks: %{}, peer_block_tasks: %{}, chain_sync_running: false},
      name: __MODULE__
    )
  end

  def init(state) do
    {:ok, state}
  end

  @spec get_peer_blocks() :: map()
  def get_peer_blocks do
    GenServer.call(__MODULE__, :get_peer_blocks)
  end

  @spec add_running_task(String.t()) :: :ok
  def add_running_task(peer_uri) do
    GenServer.call(__MODULE__, {:add_running_task, peer_uri})
  end

  @spec remove_running_task(String.t()) :: :ok
  def remove_running_task(peer_uri) do
    GenServer.call(__MODULE__, {:remove_running_task, peer_uri})
  end

  @spec get_running_tasks() :: map()
  def get_running_tasks do
    GenServer.call(__MODULE__, :get_running_tasks)
  end

  @spec chain_sync_running?() :: boolean()
  def chain_sync_running? do
    GenServer.call(__MODULE__, :get_chain_sync_status)
  end

  @spec set_chain_sync_status(boolean()) :: :ok
  def set_chain_sync_status(status) do
    GenServer.call(__MODULE__, {:set_chain_sync_status, status})
  end

  @spec add_block_to_state(binary(), Block.t()) :: :ok
  def add_block_to_state(block_hash, block) do
    GenServer.call(__MODULE__, {:add_block_to_state, block_hash, block})
  end

  @spec remove_block_from_state(binary()) :: :ok
  def remove_block_from_state(block_hash) do
    GenServer.call(__MODULE__, {:remove_block_from_state, block_hash})
  end

  @spec ask_peers_for_unknown_blocks(Peers.peers()) :: :ok
  def ask_peers_for_unknown_blocks(peers) do
    Enum.each(peers, fn {_, %{uri: uri, latest_block: top_block_hash}} ->
      top_hash_decoded = Header.base58c_decode(top_block_hash)

      if !Map.has_key?(get_running_tasks(), uri) do
        PeerBlocksTask.start_link([uri, top_hash_decoded])
      end
    end)
  end

  @spec add_peer_blocks_to_sync_state(String.t(), binary()) :: :ok
  def add_peer_blocks_to_sync_state(peer_uri, from_block_hash) do
    if Chain.has_block?(from_block_hash) do
      remove_running_task(peer_uri)
    else
      add_running_task(peer_uri)

      case HttpClient.get_raw_blocks({peer_uri, from_block_hash, Chain.top_block_hash()}) do
        {:ok, blocks} ->
          if !Enum.empty?(blocks) do
            Enum.each(blocks, fn block ->
              try do
                BlockValidation.single_validate_block!(block)

                peer_block_hash = BlockValidation.block_header_hash(block.header)

                if !Chain.has_block?(peer_block_hash) do
                  add_block_to_state(peer_block_hash, block)
                end
              catch
                {:error, message} ->
                  Logger.error(fn -> message end)
              end
            end)

            earliest_block = Enum.at(blocks, Enum.count(blocks) - 1)

            add_peer_blocks_to_sync_state(
              peer_uri,
              earliest_block.header.prev_hash
            )
          end

        {:error, message} ->
          Logger.error(fn -> message end)
          remove_running_task(peer_uri)
      end
    end
  end

  @spec add_valid_peer_blocks_to_chain(map()) :: :ok
  def add_valid_peer_blocks_to_chain(state) do
    unless chain_sync_running?() do
      set_chain_sync_status(true)

      Enum.each(state, fn {_, block} ->
        built_chain = build_chain(state, block, [])
        add_built_chain(built_chain)
      end)

      set_chain_sync_status(false)
    end
  end

  @spec add_unknown_peer_pool_txs(Peers.peers()) :: :ok
  def add_unknown_peer_pool_txs(peers) do
    peer_uris = peers |> Map.values() |> Enum.map(fn %{uri: uri} -> uri end)

    Enum.each(peer_uris, fn peer ->
      case HttpClient.get_pool_txs(peer) do
        {:ok, deserialized_pool_txs} ->
          Enum.each(deserialized_pool_txs, fn tx ->
            Pool.add_transaction(tx)
          end)

        :error ->
          Logger.error("Couldn't get pool from peer")
      end
    end)
  end

  def handle_call(:get_peer_blocks, _from, %{peer_blocks: peer_blocks} = state) do
    {:reply, peer_blocks, state}
  end

  def handle_call(
        {:add_running_task, peer_uri},
        from,
        %{peer_block_tasks: peer_block_tasks} = state
      ) do
    updated_tasks = Map.put(peer_block_tasks, peer_uri, from)

    {:reply, :ok, %{state | peer_block_tasks: updated_tasks}}
  end

  def handle_call(
        {:remove_running_task, peer_uri},
        _from,
        %{peer_block_tasks: peer_block_tasks} = state
      ) do
    updated_tasks = Map.delete(peer_block_tasks, peer_uri)

    {:reply, :ok, %{state | peer_block_tasks: updated_tasks}}
  end

  def handle_call(:get_running_tasks, _from, %{peer_block_tasks: peer_block_tasks} = state) do
    {:reply, peer_block_tasks, state}
  end

  def handle_call(
        :get_chain_sync_status,
        _from,
        %{chain_sync_running: chain_sync_running} = state
      ) do
    {:reply, chain_sync_running, state}
  end

  def handle_call({:set_chain_sync_status, status}, _from, state) do
    {:reply, :ok, %{state | chain_sync_running: status}}
  end

  def handle_call(
        {:add_block_to_state, block_hash, block},
        _from,
        %{peer_blocks: peer_blocks} = state
      ) do
    updated_peer_blocks =
      if Chain.has_block?(block_hash) do
        peer_blocks
      else
        try do
          BlockValidation.single_validate_block!(block)
          Map.put(peer_blocks, block_hash, block)
        catch
          {:error, message} ->
            Logger.error(fn -> "Can't add block to Sync state - #{message}" end)
            peer_blocks
        end
      end

    {:reply, :ok, %{state | peer_blocks: updated_peer_blocks}}
  end

  def handle_call(
        {:remove_block_from_state, block_hash},
        _from,
        %{peer_blocks: peer_blocks} = state
      ) do
    updated_peer_blocks = Map.delete(peer_blocks, block_hash)

    {:reply, :ok, %{state | peer_blocks: updated_peer_blocks}}
  end

  def handle_info(_any, state) do
    {:noreply, state}
  end

  # To make sure no peer is more popular in network then others,
  # we remove one peer at random if we have at least target_count of peers.
  @spec introduce_variety :: :ok
  def introduce_variety do
    peers_count = map_size(Peers.all_peers())

    if peers_count >= @peers_target_count do
      random_peer = Enum.random(Map.keys(Peers.all_peers()))
      Logger.info(fn -> "Removing #{random_peer} to introduce variety" end)
      Peers.remove_peer(random_peer)
      :ok
    else
      :ok
    end
  end

  # If our peer count is lower then @peers_target_count,
  # we request peers list from all known peers and choose at random
  # min(peers_we_need_to_have_target_count, peers_we_currently_have)
  # new peers to add.
  @spec refill :: :ok | {:error, term()}
  def refill do
    peers_count = map_size(Peers.all_peers())

    cond do
      peers_count == 0 ->
        {:error, "No peers"}

      peers_count < @peers_target_count ->
        all_peers =
          Peers.all_peers()
          |> Map.values()
          |> Enum.map(fn %{uri: uri} -> uri end)

        new_count = get_newpeers_and_add(all_peers)

        if new_count > 0 do
          Logger.info(fn -> "Aquired #{new_count} new peers" end)
          :ok
        else
          Logger.debug(fn ->
            "No new peers added when trying to refill peers"
          end)

          {:error, "No new peers added"}
        end

      true ->
        :ok
    end
  end

  defp get_newpeers_and_add(known) do
    known_count = length(known)
    known_set = MapSet.new(known)

    number_of_peers_to_add = Enum.min([@peers_target_count - known_count, known_count])

    known
    |> Enum.shuffle()
    |> Enum.take(@peers_target_count - known_count)
    |> Enum.reduce([], fn peer, acc ->
      case HttpClient.get_peers(peer) do
        {:ok, list} ->
          Enum.concat(acc, Enum.map(Map.values(list), fn %{"uri" => uri} -> uri end))

        {:error, message} ->
          Logger.error(fn -> "Couldn't get peers from #{peer}: #{message}" end)
          acc
      end
    end)
    |> Enum.reduce([], fn peer, acc ->
      if MapSet.member?(known_set, peer) do
        acc
      else
        [peer | acc]
      end
    end)
    |> Enum.shuffle()
    |> Enum.reduce(0, fn peer, acc ->
      # if we have successfully added less then number_of_peers_to_add peers
      # then try to add another one
      if acc < number_of_peers_to_add do
        case Peers.add_peer(peer) do
          :ok ->
            acc + 1

          _ ->
            acc
        end
      else
        acc
      end
    end)
  end

  # Builds a chain, starting from the given block,
  # until we reach a block, of which the previous block is the highest in our chain
  # (that means we can add this chain to ours)
  defp build_chain(state, block, chain) do
    has_parent_block_in_state = Map.has_key?(state, block.header.prev_hash)
    has_parent_in_chain = Chain.has_block?(block.header.prev_hash)
    block_header_hash = BlockValidation.block_header_hash(block.header)

    if Chain.has_block?(block_header_hash) do
      chain
    else
      cond do
        has_parent_block_in_state ->
          build_chain(state, state[block.header.prev_hash], [block | chain])

        has_parent_in_chain ->
          [block | chain]

        true ->
          []
      end
    end
  end

  # Adds the given chain to the local chain and
  # deletes the blocks we added from the state
  defp add_built_chain(chain) do
    Enum.each(chain, fn block ->
      case Chain.add_block(block) do
        :ok ->
          remove_block_from_state(BlockValidation.block_header_hash(block.header))

        :error ->
          Logger.info("Block couldn't be added to chain")
      end
    end)
  end
end
