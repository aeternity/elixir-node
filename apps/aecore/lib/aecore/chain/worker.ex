defmodule Aecore.Chain.Worker do
  @moduledoc """
  Module for working with chain
  """

  use GenServer
  use Bitwise

  alias Aecore.Structures.Block
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.OracleRegistrationTx
  alias Aecore.Structures.OracleQueryTx
  alias Aecore.Structures.OracleResponseTx
  alias Aecore.Structures.OracleExtendTx
  alias Aecore.Structures.Header
  alias Aecore.Structures.SpendTx
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Chain.BlockValidation
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Difficulty
  alias Aecore.Wallet.Worker, as: Wallet
  alias Aehttpserver.Web.Notify
  alias Aeutil.Serialization
  alias Aecore.Structures.Chainstate
  alias Aecore.Structures.Account
  alias Aecore.Structures.AccountStateTree

  require Logger

  @type txs_index :: %{binary() => [{binary(), binary()}]}

  # upper limit for number of blocks is 2^max_refs
  @max_refs 30

  def start_link(_args) do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  def init(_) do
    genesis_block_hash = BlockValidation.block_header_hash(Block.genesis_block().header)

    genesis_chain_state =
      Chainstate.calculate_and_validate_chain_state!(
        Block.genesis_block().txs,
        build_chain_state(),
        0
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
       top_height: 0
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

  @spec top_block_chain_state() :: Chainstate.account_chainstate()
  def top_block_chain_state do
    GenServer.call(__MODULE__, :top_block_info).chain_state
  end

  @spec top_block_hash() :: binary()
  def top_block_hash do
    GenServer.call(__MODULE__, :top_block_hash)
  end

  @spec top_height() :: non_neg_integer()
  def top_height() do
    GenServer.call(__MODULE__, :top_height)
  end

  @spec get_header_by_base58_hash(String.t()) :: Header.t() | {:error, atom()}
  def get_header_by_base58_hash(hash) do
    try do
      decoded_hash = Header.base58c_decode(hash)
      get_header(decoded_hash)
    rescue
      _ ->
        {:error, :invalid_hash}
    end
  end

  @spec lowest_valid_nonce() :: non_neg_integer()
  def lowest_valid_nonce() do
    GenServer.call(__MODULE__, :lowest_valid_nonce)
  end

  @spec get_block_by_base58_hash(String.t()) :: Block.t()
  def get_block_by_base58_hash(hash) do
    try do
      decoded_hash = Header.base58c_decode(hash)
      get_block(decoded_hash)
    rescue
      _ ->
        {:error, :invalid_hash}
    end
  end

  @spec get_header(binary()) :: Block.t() | {:error, atom()}
  def get_header(header_hash) do
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

  @spec get_header_by_height(non_neg_integer()) :: Header.t() | {:error, atom()}
  def get_header_by_height(height) do
    case get_block_info_by_height(height, nil) do
      {:error, :chain_too_short} -> {:error, :chain_too_short}
      info -> {:ok, info.block.header}
    end
  end

  @spec get_block(binary()) :: Block.t() | {:error, String.t()}
  def get_block(header_hash) do
    ## At first we are making attempt to get the block from the chain state.
    ## If there is no such block then we check into the db.
    block =
      case GenServer.call(__MODULE__, {:get_block_info_from_memory_unsafe, header_hash}) do
        {:error, _} ->
          nil

        %{block: nil} ->
          case Persistence.get_block_by_hash(header_hash) do
            {:ok, block} -> {:ok, block}
            _ -> nil
          end

        block_info ->
          {:ok, block_info.block}
      end

    if block != nil do
      block
    else
      {:error, :block_not_found}
    end
  end

  @spec get_block_by_height(non_neg_integer(), binary() | nil) :: Block.t() | {:error, binary()}
  def get_block_by_height(height, chain_hash \\ nil) do
    case get_block_info_by_height(height, chain_hash) do
      {:error, _} = error -> error
      info -> {:ok, info.block}
    end
  end

  @spec has_block?(binary()) :: boolean()
  def has_block?(hash) do
    case get_block(hash) do
      {:error, _} -> false
      _block -> true
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

  @spec get_block_by_height(non_neg_integer(), binary() | nil) ::
          Chainstate.account_chainstate() | {:error, binary()}
  def get_chain_state_by_height(height, chain_hash \\ nil) do
    case get_block_info_by_height(height, chain_hash) do
      {:error, _} = error -> error
      %{chain_state: chain_state} -> chain_state
      _ -> {:error, "Chainstate was delated"}
    end
  end

  @spec add_block(Block.t()) :: :ok | {:error, binary()}
  def add_block(%Block{} = block) do
    {:ok, prev_block} = get_block(block.header.prev_hash)
    prev_block_chain_state = chain_state(block.header.prev_hash)

    blocks_for_difficulty_calculation =
      get_blocks(block.header.prev_hash, Difficulty.get_number_of_blocks())

    new_chain_state =
      BlockValidation.calculate_and_validate_block!(
        block,
        prev_block,
        prev_block_chain_state,
        blocks_for_difficulty_calculation
      )

    add_validated_block(block, new_chain_state)
  end

  @spec add_validated_block(Block.t(), Chainstate.chainstate()) :: :ok
  defp add_validated_block(%Block{} = block, chain_state) do
    GenServer.call(__MODULE__, {:add_validated_block, block, chain_state})
  end

  @spec chain_state(binary()) :: Chainstate.t() | {:error, binary()}
  def chain_state(block_hash) do
    case GenServer.call(__MODULE__, {:get_block_info_from_memory_unsafe, block_hash}) do
      error = {:error, _} ->
        error

      %{chain_state: chain_state} ->
        chain_state

      _ ->
        {:error, "Chainstate was deleted"}
    end
  end

  @spec registered_oracles() :: Oracle.registered_oracles()
  def registered_oracles() do
    GenServer.call(__MODULE__, :registered_oracles)
  end

  @spec oracle_interaction_objects() :: Oracle.interaction_objects()
  def oracle_interaction_objects() do
    GenServer.call(__MODULE__, :oracle_interaction_objects)
  end

  @spec chain_state() :: %{
          :accounts => Chainstate.accounts(),
          :oracles => Chainstate.oracles()
        }
  def chain_state() do
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

  def handle_call(
        {:get_block_info_from_memory_unsafe, block_hash},
        _from,
        %{blocks_data_map: blocks_data_map} = state
      ) do
    block_info = blocks_data_map[block_hash]

    if block_info != nil do
      {:reply, block_info, state}
    else
      {:reply, {:error, "Block not found"}, state}
    end
  end

  def handle_call(
        {:add_validated_block, %Block{} = new_block, new_chain_state},
        _from,
        %{
          blocks_data_map: blocks_data_map,
          txs_index: txs_index,
          top_height: top_height
        } = state
      ) do
    new_block_txs_index = calculate_block_acc_txs_info(new_block)
    new_txs_index = update_txs_index(txs_index, new_block_txs_index)
    Enum.each(new_block.txs, fn tx -> Pool.remove_transaction(tx) end)
    new_block_hash = BlockValidation.block_header_hash(new_block.header)

    # refs_list is generated so it contains n-th prev blocks for n-s beeing a power of two.
    # So for chain A<-B<-C<-D<-E<-F<-G<-H. H refs will be [G,F,D,A].
    # This allows for log n findning of block with given height.
    new_refs =
      0..@max_refs
      |> Enum.reduce([new_block.header.prev_hash], fn i, [prev | _] = acc ->
        case Enum.at(blocks_data_map[prev].refs, i) do
          nil ->
            acc

          hash ->
            [hash | acc]
        end
      end)
      |> Enum.reverse()

    updated_blocks_data_map =
      Map.put(blocks_data_map, new_block_hash, %{
        block: new_block,
        chain_state: new_chain_state,
        refs: new_refs
      })

    hundred_blocks_data_map =
      remove_old_block_data_from_map(updated_blocks_data_map, new_block_hash)

    total_tokens = Chainstate.calculate_total_tokens(new_chain_state)

    Logger.info(fn ->
      "Added block ##{new_block.header.height} with hash #{Header.base58c_encode(new_block_hash)}, total tokens: #{
        inspect(total_tokens)
      }"
    end)

    state_update = %{
      state
      | blocks_data_map: hundred_blocks_data_map,
        txs_index: new_txs_index
    }

    if top_height < new_block.header.height do
      Persistence.batch_write(%{
        :chain_state => %{:chain_state => new_chain_state},
        :block => %{new_block_hash => new_block},
        :latest_block_info => %{
          :top_hash => new_block_hash,
          :top_height => new_block.header.height
        },
        :block_info => %{new_block_hash => %{refs: new_refs}}
      })

      ## We send the block to others only if it extends the longest chain
      Peers.broadcast_block(new_block)

      # Broadcasting notifications for new block added to chain and new mined transaction
      Notify.broadcast_new_block_added_to_chain_and_new_mined_tx(new_block)

      {:reply, :ok,
       %{state_update | top_hash: new_block_hash, top_height: new_block.header.height}}
    else
      Persistence.batch_write(%{
        :chain_state => %{:chain_state => new_chain_state},
        :block => %{new_block_hash => new_block},
        :block_info => %{new_block_hash => %{refs: new_refs}}
      })

      {:reply, :ok, state_update}
    end
  end

  def handle_call(:txs_index, _from, %{txs_index: txs_index} = state) do
    {:reply, txs_index, state}
  end

  def handle_call(
        :registered_oracles,
        _from,
        %{blocks_data_map: blocks_data_map, top_hash: top_hash} = state
      ) do
    registered_oracles = blocks_data_map[top_hash].chain_state.oracles.registered_oracles
    {:reply, registered_oracles, state}
  end

  def handle_call(
        :oracle_interaction_objects,
        _from,
        %{blocks_data_map: blocks_data_map, top_hash: top_hash} = state
      ) do
    interaction_objects = blocks_data_map[top_hash].chain_state.oracles.interaction_objects
    {:reply, interaction_objects, state}
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

    top_chain_state =
      case Persistence.get_all_accounts_chain_states() do
        chain_states when chain_states == %{} -> state.blocks_data_map[top_hash].chain_state
        chain_states -> chain_states
      end

    blocks_map =
      case Persistence.get_blocks(number_of_blocks_in_memory()) do
        blocks_map when blocks_map == %{} -> %{}
        blocks_map -> blocks_map
      end

    blocks_data_map =
      case Persistence.get_all_blocks_info() do
        blocks_info_map when blocks_info_map == %{} ->
          state.blocks_data_map

        blocks_info_map ->
          blocks_info_map
          |> Map.merge(blocks_map, fn _hash, info, block ->
            Map.put(info, :block, block)
          end)
          |> Map.update!(top_hash, fn info ->
            Map.put(info, :chain_state, top_chain_state)
          end)
      end

    {:noreply,
     %{state | blocks_data_map: blocks_data_map, top_hash: top_hash, top_height: top_height}}
  end

  defp remove_old_block_data_from_map(block_map, top_hash) do
    if block_map[top_hash].block.header.height > number_of_blocks_in_memory() do
      hash_to_remove = get_nth_prev_hash(number_of_blocks_in_memory(), top_hash, block_map)
      Logger.info("Block ##{hash_to_remove} has been removed from memory")

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
            [tx.data.sender, tx.data.payload.receiver]

          OracleRegistrationTx ->
            tx.data.sender

          OracleQueryTx ->
            [tx.data.sender, tx.data.payload.oracle_address]

          OracleResponseTx ->
            tx.data.sender

          OracleExtendTx ->
            tx.data.sender

          _ ->
            tx.data.sender
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
              tx.data.sender == account || tx.data.payload.receiver == account

            _ ->
              tx.data.sender == account
          end
        end)
        |> Enum.map(fn filtered_tx ->
          tx_bin = Serialization.pack_binary(filtered_tx)
          hash = :crypto.hash(:sha256, tx_bin)
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

  defp get_block_info_by_height(height, chain_hash) do
    begin_hash =
      if chain_hash == nil do
        top_block_hash()
      else
        chain_hash
      end

    blocks_data_map = GenServer.call(__MODULE__, :blocks_data_map)
    n = blocks_data_map[begin_hash].block.header.height - height

    if n < 0 do
      {:error, :chain_too_short}
    else
      block_hash = get_nth_prev_hash(n, begin_hash, blocks_data_map)

      case blocks_data_map[block_hash] do
        %{block: nil} = block_info ->
          case Persistence.get_block_by_hash(block_hash) do
            {:ok, block} -> %{block_info | block: block}
            _ -> block_info
          end

        block_info ->
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

  defp build_chain_state, do: Chainstate.init()
end
