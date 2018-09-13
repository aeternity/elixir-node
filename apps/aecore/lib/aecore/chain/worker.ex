defmodule Aecore.Chain.Worker do
  @moduledoc """
  Module containing Chain interaction functionality
  """

  use GenServer
  use Bitwise

  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Keys
  alias Aecore.Account.{Account, AccountStateTree}
  alias Aecore.Governance.GovernanceConstants
  alias Aehttpserver.Web.Notify
  alias Aecore.Chain.{Header, BlockValidation, Block, Chainstate, Genesis}
  alias Aeutil.{Serialization, Scientific, PatriciaMerkleTree, Events}

  require Logger

  @type reason :: atom()

  # upper limit for number of blocks is 2^max_refs
  @max_refs 30

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_args) do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  def init(_) do
    genesis_block_header = Genesis.block().header
    genesis_block_hash = Header.hash(genesis_block_header)

    {:ok, genesis_chain_state} =
      Chainstate.calculate_and_validate_chain_state(
        Genesis.block().txs,
        build_chain_state(),
        genesis_block_header.height,
        genesis_block_header.miner
      )

    blocks_data_map = %{
      genesis_block_hash => %{
        block: Genesis.block(),
        chain_state: genesis_chain_state,
        refs: []
      }
    }

    {:ok,
     %{
       blocks_data_map: blocks_data_map,
       top_hash: genesis_block_hash,
       top_height: 0,
       total_diff: Persistence.get_total_difficulty()
     }, 0}
  end

  @spec clear_state() :: :ok
  def clear_state, do: GenServer.call(__MODULE__, :clear_state)

  @spec top_block() :: Block.t()
  def top_block do
    GenServer.call(__MODULE__, :top_block_info).block
  end

  @spec current_state() :: Block.t()
  def current_state do
    GenServer.call(__MODULE__, :current_state)
  end

  @spec top_block_chain_state() :: Chainstate.t()
  def top_block_chain_state do
    GenServer.call(__MODULE__, :top_block_info).chain_state
  end

  @spec top_block_hash() :: binary()
  def top_block_hash do
    GenServer.call(__MODULE__, :top_block_hash)
  end

  @spec top_height() :: non_neg_integer()
  def top_height do
    GenServer.call(__MODULE__, :top_height)
  end

  @spec get_header_by_base58_hash(String.t()) :: Header.t() | {:error, reason()}
  def get_header_by_base58_hash(hash) do
    decoded_hash = Header.base58c_decode(hash)
    get_header_by_hash(decoded_hash)
  rescue
    _ ->
      {:error, :invalid_hash}
  end

  @spec lowest_valid_nonce() :: non_neg_integer()
  def lowest_valid_nonce do
    GenServer.call(__MODULE__, :lowest_valid_nonce)
  end

  @spec total_difficulty() :: non_neg_integer()
  def total_difficulty do
    GenServer.call(__MODULE__, :total_difficulty)
  end

  @spec get_block_by_base58_hash(String.t()) :: {:ok, Block.t()} | {:error, String.t() | atom()}
  def get_block_by_base58_hash(hash) do
    decoded_hash = Header.base58c_decode(hash)
    get_block(decoded_hash)
  rescue
    _ ->
      {:error, :invalid_hash}
  end

  @spec get_headers_forward(binary(), non_neg_integer()) ::
          {:ok, list(Header.t())} | {:error, atom()}
  def get_headers_forward(starting_hash, count) do
    case get_header_by_hash(starting_hash) do
      {:ok, %Header{height: height}} ->
        blocks_to_get = min(top_height() - height, count)

        ## Start from the first block we don't have
        start_from = height + 1
        get_headers_forward([], start_from, blocks_to_get)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec get_header_by_hash(binary()) :: {:ok, Header.t()} | {:error, reason()}
  def get_header_by_hash(header_hash) do
    case GenServer.call(__MODULE__, {:get_block_info_from_memory_unsafe, header_hash}) do
      {:error, _reason} ->
        {:error, :header_not_found}

      %{block: nil} ->
        case Persistence.get_block_by_hash(header_hash) do
          {:ok, %Block{header: header}} -> {:ok, header}
          _ -> {:error, :header_not_found}
        end

      %{block: %Block{header: header}} ->
        {:ok, header}
    end
  end

  @spec hash_is_in_main_chain?(binary()) :: boolean()
  def hash_is_in_main_chain?(header_hash) do
    longest_blocks_chain()
    |> Enum.map(fn block -> Header.hash(block.header) end)
    |> Enum.member?(header_hash)
  end

  @spec get_header_by_height(non_neg_integer()) :: Header.t() | {:error, reason()}
  def get_header_by_height(height) do
    case get_block_info_by_height(height, nil, :block) do
      {:error, :chain_too_short} -> {:error, :chain_too_short}
      %{block: %Block{header: header}} -> {:ok, header}
    end
  end

  @spec get_block(binary()) :: {:ok, Block.t()} | {:error, String.t() | atom()}
  def get_block(block_hash) do
    # At first we are making attempt to get the block from the chain state.
    # If there is no such block then we check the db.
    case GenServer.call(__MODULE__, {:get_block_info_from_memory_unsafe, block_hash}) do
      {:error, _} = err ->
        err

      %{block: nil} ->
        case Persistence.get_block_by_hash(block_hash) do
          {:ok, block} ->
            {:ok, block}

          _ ->
            {:error, "#{__MODULE__}: Block not found for hash [#{block_hash}]"}
        end

      %{block: block} ->
        {:ok, block}
    end
  end

  @spec get_block_by_height(non_neg_integer(), binary() | nil) ::
          {:ok, Block.t()} | {:error, binary()}
  def get_block_by_height(height, chain_hash \\ nil) do
    case get_block_info_by_height(height, chain_hash, :block) do
      {:error, _} = error -> error
      %{block: block} -> {:ok, block}
    end
  end

  @spec has_block?(binary()) :: boolean()
  def has_block?(hash) do
    case get_block(hash) do
      {:ok, _block} -> true
      {:error, _} -> false
    end
  end

  @spec get_blocks(binary(), non_neg_integer()) :: list(Block.t())
  def get_blocks(start_block_hash, count) do
    Enum.reverse(get_blocks([], start_block_hash, nil, count))
  end

  @spec get_blocks(binary(), binary(), non_neg_integer()) :: list(Block.t())
  def get_blocks(start_block_hash, final_block_hash, count) do
    Enum.reverse(get_blocks([], start_block_hash, final_block_hash, count))
  end

  @spec get_chain_state_by_height(non_neg_integer(), binary() | nil) ::
          Chainstate.t() | {:error, String.t()}
  def get_chain_state_by_height(height, chain_hash \\ nil) do
    case get_block_info_by_height(height, chain_hash, :chainstate) do
      {:error, _} = error ->
        error

      %{chain_state: chain_state} ->
        chain_state

      _ ->
        {:error, "#{__MODULE__}: Chainstate was delated"}
    end
  end

  @spec add_block(Block.t()) :: :ok | {:error, String.t()}
  def add_block(%Block{header: %Header{prev_hash: prev_hash}} = block) do
    with {:ok, prev_block} <- get_block(prev_hash),
         {:ok, prev_block_chain_state} <- chain_state(prev_hash),
         blocks_for_target_calculation =
           get_blocks(
             prev_hash,
             GovernanceConstants.number_of_blocks_for_target_recalculation()
           ),
         {:ok, new_chain_state} <-
           BlockValidation.calculate_and_validate_block(
             block,
             prev_block,
             prev_block_chain_state,
             blocks_for_target_calculation
           ) do
      add_validated_block(block, new_chain_state)
    else
      err -> err
    end
  end

  @spec add_validated_block(Block.t(), Chainstate.t()) :: :ok
  defp add_validated_block(%Block{} = block, chain_state) do
    GenServer.call(__MODULE__, {:add_validated_block, block, chain_state})
  end

  @spec chain_state(binary()) :: {:ok, Chainstate.t()} | {:error, String.t()}
  def chain_state(block_hash) do
    case GenServer.call(__MODULE__, {:get_block_info_from_memory_unsafe, block_hash}) do
      {:error, _} = err ->
        err

      %{chain_state: chain_state} ->
        {:ok, chain_state}

      _ ->
        {:error, "#{__MODULE__}: Chainstate was deleted"}
    end
  end

  @spec chain_state() :: Chainstate.t()
  def chain_state do
    top_block_chain_state()
  end

  @spec longest_blocks_chain() :: list(Block.t())
  def longest_blocks_chain do
    get_blocks(top_block_hash(), top_height() + 1)
  end

  def handle_call(:clear_state, _from, _state) do
    {:ok, new_state, _} = init(:empty)
    {:reply, :ok, new_state}
  end

  def handle_call(:current_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(
        :top_block_info,
        _from,
        %{blocks_data_map: blocks_data_map, top_hash: top_hash} = state
      ) do
    {:reply, blocks_data_map[top_hash], state}
  end

  def handle_call(:top_block_hash, _from, %{top_hash: top_hash} = state) do
    {:reply, top_hash, state}
  end

  def handle_call(:top_height, _from, %{top_height: top_height} = state) do
    {:reply, top_height, state}
  end

  def handle_call(
        :lowest_valid_nonce,
        _from,
        %{blocks_data_map: blocks_data_map, top_hash: top_hash} = state
      ) do
    {pubkey, _} = Keys.keypair(:sign)
    accounts_state_tree = blocks_data_map[top_hash].chain_state.accounts

    lowest_valid_nonce =
      if AccountStateTree.has_key?(accounts_state_tree, pubkey) do
        Account.nonce(accounts_state_tree, pubkey) + 1
      else
        1
      end

    {:reply, lowest_valid_nonce, state}
  end

  def handle_call(:total_difficulty, _from, %{total_diff: total_diff} = state) do
    {:reply, total_diff, state}
  end

  def handle_call(
        {:get_block_info_from_memory_unsafe, block_hash},
        _from,
        %{blocks_data_map: blocks_data_map} = state
      ) do
    case Map.fetch(blocks_data_map, block_hash) do
      {:ok, block_info} ->
        {:reply, block_info, state}

      :error ->
        {:reply, {:error, "#{__MODULE__}: Block not found with hash [#{block_hash}]"}, state}
    end
  end

  def handle_call(
        {:add_validated_block,
         %Block{
           header: %Header{prev_hash: prev_hash, height: height, target: target} = header,
           txs: txs
         } = new_block, new_chain_state},
        _from,
        %{
          blocks_data_map: blocks_data_map,
          top_height: top_height,
          total_diff: total_diff
        } = state
      ) do
    Enum.each(txs, fn tx -> Pool.remove_transaction(tx) end)
    new_block_hash = Header.hash(header)

    # refs_list is generated so it contains n-th prev blocks for n-s beeing a power of two.
    # So for chain A<-B<-C<-D<-E<-F<-G<-H. H refs will be [G,F,D,A].
    # This allows for log n findning of block with a given height.

    new_refs = refs(@max_refs, blocks_data_map, prev_hash)

    updated_blocks_data_map =
      Map.put(blocks_data_map, new_block_hash, %{
        block: new_block,
        chain_state: new_chain_state,
        refs: new_refs
      })

    hundred_blocks_data_map =
      remove_old_block_data_from_map(updated_blocks_data_map, new_block_hash)

    Logger.info(fn ->
      "#{__MODULE__}: Added block ##{height}
      with hash #{Header.base58c_encode(new_block_hash)}"
    end)

    state_update = %{
      state
      | blocks_data_map: hundred_blocks_data_map
    }

    new_total_diff = total_diff + Scientific.target_to_difficulty(target)

    if top_height < height do
      Persistence.batch_write(%{
        # Transfrom from chain state
        :chain_state => %{
          new_block_hash =>
            transform_chainstate(:from_chainstate, {:ok, Map.from_struct(new_chain_state)})
        },
        :block => %{new_block_hash => new_block},
        :latest_block_info => %{
          :top_hash => new_block_hash,
          :top_height => height
        },
        :block_info => %{new_block_hash => %{refs: new_refs}},
        :total_diff => %{:total_difficulty => new_total_diff}
      })

      Events.publish(:new_top_block, new_block)

      # Broadcasting notifications for new block added to chain and new mined transaction
      Notify.broadcast_new_block_added_to_chain_and_new_mined_tx(new_block)

      {:reply, :ok,
       %{
         state_update
         | top_hash: new_block_hash,
           top_height: height,
           total_diff: new_total_diff
       }}
    else
      Persistence.batch_write(%{
        :chain_state => %{
          new_block_hash =>
            transform_chainstate(:from_chainstate, {:ok, Map.from_struct(new_chain_state)})
        },
        :block => %{new_block_hash => new_block},
        :block_info => %{new_block_hash => %{refs: new_refs}}
      })

      {:reply, :ok, state_update}
    end
  end

  def handle_call(:blocks_data_map, _from, %{blocks_data_map: blocks_data_map} = state) do
    {:reply, blocks_data_map, state}
  end

  def handle_info(
        :timeout,
        %{top_hash: top_hash, top_height: top_height, blocks_data_map: blocks_data_map} = state
      ) do
    {top_hash, top_height} =
      case Persistence.get_latest_block_height_and_hash() do
        :not_found -> {top_hash, top_height}
        {:ok, %{hash: hash, height: height}} -> {hash, height}
      end

    blocks_map = Persistence.get_blocks(number_of_blocks_in_memory())
    blocks_info = Persistence.get_all_blocks_info()

    if Enum.empty?(blocks_map) do
      [block_hash] = Map.keys(state.blocks_data_map)
      genesis_block = blocks_data_map[block_hash].block
      genesis_chainstate = blocks_data_map[block_hash].chain_state

      spawn(fn ->
        add_validated_block(genesis_block, genesis_chainstate)
      end)
    end

    is_empty_block_info = blocks_info |> Serialization.remove_struct() |> Enum.empty?()

    blocks_data_map =
      if is_empty_block_info do
        blocks_data_map
      else
        blocks_info
        |> Enum.map(fn {hash, %{refs: refs}} ->
          block = Map.get(blocks_map, hash, nil)

          chain_state =
            if block == nil do
              nil
            else
              struct(
                Chainstate,
                transform_chainstate(:to_chainstate, Persistence.get_all_chainstates(hash))
              )
            end

          {hash, %{refs: refs, block: block, chain_state: chain_state}}
        end)
        |> Enum.into(%{})
      end

    {:noreply,
     %{state | blocks_data_map: blocks_data_map, top_hash: top_hash, top_height: top_height}}
  end

  defp remove_old_block_data_from_map(block_map, top_hash) do
    %{block: %Block{header: %Header{height: top_block_height}}} = block_map[top_hash]

    if top_block_height + 1 > number_of_blocks_in_memory() do
      hash_to_remove = get_nth_prev_hash(number_of_blocks_in_memory(), top_hash, block_map)
      Logger.info("#{__MODULE__}: Block ##{hash_to_remove} has been removed from memory")

      Map.update!(block_map, hash_to_remove, fn info ->
        %{info | block: nil, chain_state: nil}
      end)
    else
      block_map
    end
  end

  defp get_blocks(blocks_acc, next_block_hash, final_block_hash, count) do
    if next_block_hash != final_block_hash && count > 0 do
      case get_block(next_block_hash) do
        {:ok, %Block{header: %Header{prev_hash: prev_hash}} = block} ->
          updated_blocks_acc = [block | blocks_acc]
          next_count = count - 1

          get_blocks(
            updated_blocks_acc,
            prev_hash,
            final_block_hash,
            next_count
          )

        {:error, _} ->
          blocks_acc
      end
    else
      blocks_acc
    end
  end

  defp number_of_blocks_in_memory do
    Application.get_env(:aecore, :persistence)[:number_of_blocks_in_memory]
  end

  defp get_headers_forward(headers, _next_header_height, 0) do
    {:ok, headers}
  end

  defp get_headers_forward(headers, next_header_height, count) when count > 0 do
    case get_header_by_height(next_header_height) do
      {:ok, %Header{height: height} = header} ->
        get_headers_forward([header | headers], height + 1, count - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_block_info_by_height(height, nil, info) do
    get_block_info_by_height(height, top_block_hash(), info)
  end

  defp get_block_info_by_height(height, begin_hash, info) do
    blocks_data_map = GenServer.call(__MODULE__, :blocks_data_map)
    n = blocks_data_map[begin_hash].block.header.height - height

    if n < 0 do
      {:error, :chain_too_short}
    else
      block_hash = get_nth_prev_hash(n, begin_hash, blocks_data_map)

      case {info, blocks_data_map[block_hash]} do
        {:block, %{block: nil} = block_info} ->
          case Persistence.get_block_by_hash(block_hash) do
            {:ok, block} -> %{block_info | block: block}
            _ -> block_info
          end

        {:chainstate, %{chain_state: nil} = block_info} ->
          case Persistence.get_all_chainstates(block_hash) do
            {:ok, chainstate} ->
              constructed_chainstate =
                struct(
                  Chainstate,
                  transform_chainstate(
                    :to_chainstate,
                    chainstate
                  )
                )

              %{block_info | chain_state: constructed_chainstate}

            _ ->
              block_info
          end

        {_, block_info} ->
          block_info
      end
    end
  end

  # get_nth_prev_hash - traverses block_data_map using the refs.
  # Becouse refs contain hashes of 1,2,4,8,16,... prev blocks we can do it fast.
  # Lets look at the height difference as a binary representation.
  # Eg. Lets say we want to go 10110 blocks back in the tree.
  # Instead of using prev_block 10110 times we can go back by 2 blocks then by 4 and by 16.
  # We can go back by such numbers of blocks becouse we have the refs.
  # This way we did 3 operations instead of 22. In general we do O(log n) operations
  # to go back by n blocks.
  defp get_nth_prev_hash(n, begin_hash, blocks_data_map) do
    get_nth_prev_hash(n, 0, begin_hash, blocks_data_map)
  end

  defp get_nth_prev_hash(0, _exponent, hash, _blocks_data_map) do
    hash
  end

  defp get_nth_prev_hash(n, exponent, hash, blocks_data_map) do
    if (n &&& 1 <<< exponent) != 0 do
      get_nth_prev_hash(
        n - (1 <<< exponent),
        exponent + 1,
        Enum.at(blocks_data_map[hash].refs, exponent),
        blocks_data_map
      )
    else
      get_nth_prev_hash(n, exponent + 1, hash, blocks_data_map)
    end
  end

  def transform_chainstate(_, {:error, _}), do: %{}

  def transform_chainstate(strategy, {:ok, chainstate}) do
    Enum.reduce(chainstate, %{}, get_persist_strategy(strategy))
  end

  defp get_persist_strategy(:to_chainstate) do
    fn
      {key = :naming, root_hash}, acc_state ->
        Map.put(acc_state, key, PatriciaMerkleTree.new(key, root_hash))

      {key = :accounts, root_hash}, acc_state ->
        Map.put(acc_state, key, PatriciaMerkleTree.new(key, root_hash))

      {_key = :oracles,
       %{oracle_tree: oracle_root_hash, oracle_cache_tree: oracle_cache_root_hash}},
      acc_state ->
        oracle_tree = %{:oracle_tree => PatriciaMerkleTree.new(:oracles, oracle_root_hash)}

        oracle_cache_tree = %{
          :oracle_cache_tree => PatriciaMerkleTree.new(:oracles_cache, oracle_cache_root_hash)
        }

        put_in(acc_state, [:oracles], Map.merge(oracle_tree, oracle_cache_tree))

      {key = :channels, root_hash}, acc_state ->
        Map.put(acc_state, key, PatriciaMerkleTree.new(key, root_hash))

      {key = :contracts, root_hash}, acc_state ->
        Map.put(acc_state, key, PatriciaMerkleTree.new(key, root_hash))

      {key = :calls, root_hash}, acc_state ->
        Map.put(acc_state, key, PatriciaMerkleTree.new(key, root_hash))
    end
  end

  defp get_persist_strategy(:from_chainstate) do
    fn
      {key = :accounts, value}, acc_state ->
        Map.put(acc_state, key, value.root_hash)

      {key = :naming, value}, acc_state ->
        Map.put(acc_state, key, value.root_hash)

      {key = :oracles, value}, acc_state ->
        Map.put(acc_state, key, %{
          oracle_tree: value.oracle_tree.root_hash,
          oracle_cache_tree: value.oracle_cache_tree.root_hash
        })

      {key = :channels, value}, acc_state ->
        Map.put(acc_state, key, value.root_hash)

      {key = :contracts, value}, acc_state ->
        Map.put(acc_state, key, value.root_hash)

      {key = :calls, value}, acc_state ->
        Map.put(acc_state, key, value.root_hash)
    end
  end

  defp build_chain_state, do: Chainstate.init()

  defp refs(_, _, <<0::32-unit(8)>>), do: []

  defp refs(max_refs, blocks_data_map, prev_hash) do
    refs_num = min(max_refs, length(blocks_data_map[prev_hash].refs) + 1)
    get_refs(refs_num, blocks_data_map, prev_hash)
  end

  defp get_refs(num_refs, blocks_data_map, prev_hash) do
    0..num_refs
    |> Enum.reduce([prev_hash], fn i, [prev | _] = acc ->
      with true <- Map.has_key?(blocks_data_map, prev),
           {:ok, hash} <- Enum.fetch(blocks_data_map[prev].refs, i) do
        [hash | acc]
      else
        :error ->
          acc

        _ ->
          Logger.error("#{__MODULE__}: Missing block with hash #{prev}")
          acc
      end
    end)
    |> Enum.reverse()
  end
end
