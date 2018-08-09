defmodule Aecore.Chain.Worker do
  @moduledoc """
  Module for working with chain
  """

  use GenServer
  use Bitwise

  alias Aecore.Chain.Block
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Oracle.Tx.OracleQueryTx
  alias Aecore.Chain.Header
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Chain.BlockValidation
  alias Aeutil.Events
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Keys.Wallet
  alias Aehttpserver.Web.Notify
  alias Aeutil.Serialization
  alias Aeutil.Hash
  alias Aeutil.Scientific
  alias Aecore.Chain.Chainstate
  alias Aecore.Account.Account
  alias Aecore.Account.AccountStateTree
  alias Aecore.Naming.Tx.NameTransferTx
  alias Aeutil.PatriciaMerkleTree
  alias Aecore.Governance.GovernanceConstants

  require Logger

  @type txs_index :: %{binary() => [{binary(), binary()}]}
  @type reason :: atom()

  # upper limit for number of blocks is 2^max_refs
  @max_refs 30

  def start_link(_args) do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  def init(_) do
    genesis_block_header = Block.genesis_block().header
    genesis_block_hash = BlockValidation.block_header_hash(genesis_block_header)

    {:ok, genesis_chain_state} =
      Chainstate.calculate_and_validate_chain_state(
        Block.genesis_block().txs,
        build_chain_state(),
        genesis_block_header.height,
        genesis_block_header.miner
      )

    blocks_data_map = %{
      genesis_block_hash => %{
        block: Block.genesis_block(),
        chain_state: genesis_chain_state,
        refs: []
      }
    }

    txs_index = calculate_block_acc_txs_info(Block.genesis_block())

    {:ok,
     %{
       blocks_data_map: blocks_data_map,
       txs_index: txs_index,
       top_hash: genesis_block_hash,
       top_height: 0,
       total_diff: Persistence.get_total_difficulty()
     }, 0}
  end

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
  def get_headers_forward(starting_header, count) do
    case get_header_by_hash(starting_header) do
      {:ok, header} ->
        blocks_to_get = min(top_height() - header.height, count)
        get_headers_forward([], header.height, blocks_to_get + 1)

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
          {:ok, block} -> {:ok, block.header}
          _ -> {:error, :header_not_found}
        end

      block_info ->
        {:ok, block_info.block.header}
    end
  end

  @spec get_header_by_height(non_neg_integer()) :: Header.t() | {:error, reason()}
  def get_header_by_height(height) do
    case get_block_info_by_height(height, nil, :block) do
      {:error, :chain_too_short} -> {:error, :chain_too_short}
      info -> {:ok, info.block.header}
    end
  end

  @spec get_block(binary()) :: {:ok, Block.t()} | {:error, String.t() | atom()}
  def get_block(block_hash) do
    ## At first we are making attempt to get the block from the chain state.
    ## If there is no such block then we check into the db.
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

      block_info ->
        {:ok, block_info.block}
    end
  end

  @spec get_block_by_height(non_neg_integer(), binary() | nil) ::
          {:ok, Block.t()} | {:error, binary()}
  def get_block_by_height(height, chain_hash \\ nil) do
    case get_block_info_by_height(height, chain_hash, :block) do
      {:error, _} = error -> error
      info -> {:ok, info.block}
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
  def add_block(%Block{} = block) do
    with {:ok, prev_block} <- get_block(block.header.prev_hash),
         {:ok, prev_block_chain_state} <- chain_state(block.header.prev_hash),
         blocks_for_target_calculation =
           get_blocks(
             block.header.prev_hash,
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

  @spec txs_index() :: txs_index()
  def txs_index do
    GenServer.call(__MODULE__, :txs_index)
  end

  @spec longest_blocks_chain() :: list(Block.t())
  def longest_blocks_chain do
    get_blocks(top_block_hash(), top_height() + 1)
  end

  ## Server side

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
    pubkey = Wallet.get_public_key()
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
        {:add_validated_block, %Block{} = new_block, new_chain_state},
        _from,
        %{
          blocks_data_map: blocks_data_map,
          txs_index: txs_index,
          top_height: top_height,
          total_diff: total_diff
        } = state
      ) do
    new_block_txs_index = calculate_block_acc_txs_info(new_block)
    new_txs_index = update_txs_index(txs_index, new_block_txs_index)
    Enum.each(new_block.txs, fn tx -> Pool.remove_transaction(tx) end)
    new_block_hash = BlockValidation.block_header_hash(new_block.header)

    # refs_list is generated so it contains n-th prev blocks for n-s beeing a power of two.
    # So for chain A<-B<-C<-D<-E<-F<-G<-H. H refs will be [G,F,D,A].
    # This allows for log n findning of block with given height.

    new_refs = refs(@max_refs, blocks_data_map, new_block.header.prev_hash)

    updated_blocks_data_map =
      Map.put(blocks_data_map, new_block_hash, %{
        block: new_block,
        chain_state: new_chain_state,
        refs: new_refs
      })

    hundred_blocks_data_map =
      remove_old_block_data_from_map(updated_blocks_data_map, new_block_hash)

    Logger.info(fn ->
      "#{__MODULE__}: Added block ##{new_block.header.height}
      with hash #{Header.base58c_encode(new_block_hash)}"
    end)

    state_update = %{
      state
      | blocks_data_map: hundred_blocks_data_map,
        txs_index: new_txs_index
    }

    new_total_diff = total_diff + Scientific.target_to_difficulty(new_block.header.target)

    if top_height < new_block.header.height do
      Persistence.batch_write(%{
        ## Transfrom from chain state
        :chain_state => %{
          new_block_hash =>
            transform_chainstate(:from_chainstate, {:ok, Map.from_struct(new_chain_state)})
        },
        :block => %{new_block_hash => new_block},
        :latest_block_info => %{
          :top_hash => new_block_hash,
          :top_height => new_block.header.height
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
           top_height: new_block.header.height,
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

  def handle_call(:txs_index, _from, %{txs_index: txs_index} = state) do
    {:reply, txs_index, state}
  end

  def handle_call(:blocks_data_map, _from, %{blocks_data_map: blocks_data_map} = state) do
    {:reply, blocks_data_map, state}
  end

  def handle_info(:timeout, state) do
    {top_hash, top_height} =
      case Persistence.get_latest_block_height_and_hash() do
        :not_found -> {state.top_hash, state.top_height}
        {:ok, latest_block} -> {latest_block.hash, latest_block.height}
      end

    blocks_map = Persistence.get_blocks(number_of_blocks_in_memory())
    blocks_info = Persistence.get_all_blocks_info()

    if Enum.empty?(blocks_map) do
      [block_hash] = Map.keys(state.blocks_data_map)
      genesis_block = state.blocks_data_map[block_hash].block
      genesis_chainstate = state.blocks_data_map[block_hash].chain_state

      spawn(fn ->
        add_validated_block(genesis_block, genesis_chainstate)
      end)
    end

    is_empty_block_info = blocks_info |> Serialization.remove_struct() |> Enum.empty?()

    blocks_data_map =
      if is_empty_block_info do
        state.blocks_data_map
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
    if block_map[top_hash].block.header.height + 1 > number_of_blocks_in_memory() do
      hash_to_remove = get_nth_prev_hash(number_of_blocks_in_memory(), top_hash, block_map)
      Logger.info("#{__MODULE__}: Block ##{hash_to_remove} has been removed from memory")

      Map.update!(block_map, hash_to_remove, fn info ->
        %{info | block: nil, chain_state: nil}
      end)
    else
      block_map
    end
  end

  defp calculate_block_acc_txs_info(block) do
    block_hash = BlockValidation.block_header_hash(block.header)

    accounts_unique =
      block.txs
      |> Enum.map(fn tx ->
        case tx.data.type do
          SpendTx ->
            [tx.data.payload.receiver | tx.data.senders]

          OracleQueryTx ->
            [tx.data.payload.oracle_address | tx.data.senders]

          NameTransferTx ->
            [tx.data.payload.target | tx.data.senders]

          _ ->
            tx.data.senders
        end
      end)
      |> List.flatten()
      |> Enum.uniq()
      |> List.delete(nil)

    for account <- accounts_unique, into: %{} do
      # txs associated with the given account
      tx_tuples =
        block.txs
        |> Enum.filter(fn tx ->
          case tx.data.type do
            SpendTx ->
              tx.data.senders == [account] || tx.data.payload.receiver == account

            _ ->
              tx.data.senders == [account]
          end
        end)
        |> Enum.map(fn filtered_tx ->
          tx_bin = Serialization.rlp_encode(filtered_tx, :signedtx)
          hash = Hash.hash(tx_bin)
          {block_hash, hash}
        end)

      {account, tx_tuples}
    end
  end

  defp update_txs_index(prev_txs_index, new_txs_index) do
    Map.merge(prev_txs_index, new_txs_index, fn _, current_txs_index, new_txs_index ->
      current_txs_index ++ new_txs_index
    end)
  end

  defp get_blocks(blocks_acc, next_block_hash, final_block_hash, count) do
    if next_block_hash != final_block_hash && count > 0 do
      case get_block(next_block_hash) do
        {:ok, block} ->
          updated_blocks_acc = [block | blocks_acc]
          prev_block_hash = block.header.prev_hash
          next_count = count - 1

          get_blocks(
            updated_blocks_acc,
            prev_block_hash,
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

  defp get_headers_forward(headers, next_header_height, count) when count > 0 do
    case get_header_by_height(next_header_height) do
      {:ok, header} ->
        get_headers_forward([header | headers], header.height + 1, count - 1)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_headers_forward(headers, _next_header_height, count) when count == 0 do
    {:ok, headers}
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
              ch_state =
                struct(
                  Chainstate,
                  transform_chainstate(
                    :to_chainstate,
                    chainstate
                  )
                )

              %{block_info | chain_state: ch_state}

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
