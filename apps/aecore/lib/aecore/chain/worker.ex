defmodule Aecore.Chain.Worker do
  @moduledoc """
  Module for working with chain
  """

  use GenServer

  alias Aecore.Structures.Block
  alias Aecore.Structures.SpendTx
  alias Aecore.Structures.OracleRegistrationTxData
  alias Aecore.Structures.OracleQueryTxData
  alias Aecore.Structures.OracleResponseTxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Structures.Header
  alias Aecore.Oracle.Oracle
  alias Aecore.Chain.ChainState
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aecore.Chain.BlockValidation
  alias Aecore.Peers.Worker, as: Peers
  alias Aecore.Persistence.Worker, as: Persistence
  alias Aecore.Chain.Difficulty
  alias Aecore.Keys.Worker, as: Keys
  alias Aehttpserver.Web.Notify
  alias Aeutil.Bits

  require Logger

  @typep txs_index :: %{binary() => [{binary(), binary()}]}

  def start_link(_args) do
    GenServer.start_link(__MODULE__, {}, name: __MODULE__)
  end

  def init(_) do
    genesis_block_hash = BlockValidation.block_header_hash(Block.genesis_block().header)
    genesis_block_map = %{genesis_block_hash => Block.genesis_block()}

    genesis_chain_state =
      ChainState.calculate_and_validate_chain_state!(Block.genesis_block().txs, %{}, 0)

    chain_states = %{genesis_block_hash => genesis_chain_state}

    txs_index = calculate_block_acc_txs_info(Block.genesis_block())

    registered_oracles = generate_registered_oracles_map(Block.genesis_block(), %{})

    oracle_interaction_objects =
      generate_oracle_interaction_objects_map(Block.genesis_block(), %{})

    {:ok,
     %{
       blocks_map: genesis_block_map,
       chain_states: chain_states,
       txs_index: txs_index,
       registered_oracles: registered_oracles,
       oracle_interaction_objects: oracle_interaction_objects,
       top_hash: genesis_block_hash,
       top_height: 0
     }}
  end

  @spec top_block() :: Block.t()
  def top_block() do
    GenServer.call(__MODULE__, :top_block)
  end

  @spec top_block_chain_state() :: tuple()
  def top_block_chain_state() do
    GenServer.call(__MODULE__, :top_block_chain_state)
  end

  @spec top_block_hash() :: binary()
  def top_block_hash() do
    GenServer.call(__MODULE__, :top_block_hash)
  end

  @spec top_height() :: integer()
  def top_height() do
    GenServer.call(__MODULE__, :top_height)
  end

  @spec lowest_valid_nonce() :: integer()
  def lowest_valid_nonce() do
    GenServer.call(__MODULE__, :lowest_valid_nonce)
  end

  @spec get_block_by_bech32_hash(String.t()) :: Block.t()
  def get_block_by_bech32_hash(hash) do
    decoded_hash = Bits.bech32_decode(hash)
    GenServer.call(__MODULE__, {:get_block_from_memory_unsafe, decoded_hash})
  end

  @spec get_block(binary()) :: Block.t()
  def get_block(block_hash) do
    ## At first we are making attempt to get the block from the chain state.
    ## If there is no such block then we check into the db.
    block =
      case GenServer.call(__MODULE__, {:get_block_from_memory_unsafe, block_hash}) do
        {:error, _} ->
          case Persistence.get_block_by_hash(block_hash) do
            {:ok, block} -> block
            _ -> nil
          end

        block ->
          block
      end

    if block != nil do
      block
    else
      {:error, "Block not found"}
    end
  end

  @spec has_block?(binary()) :: boolean()
  def has_block?(hash) do
    case get_block(hash) do
      {:error, _} -> false
      _ -> true
    end
  end

  @spec get_blocks(binary(), integer()) :: list(Block.t())
  def get_blocks(start_block_hash, count) do
    Enum.reverse(get_blocks([], start_block_hash, nil, count))
  end

  @spec get_blocks(binary(), binary(), integer()) :: list(Block.t())
  def get_blocks(start_block_hash, final_block_hash, count) do
    Enum.reverse(get_blocks([], start_block_hash, final_block_hash, count))
  end

  @spec add_block(Block.t()) :: :ok | {:error, binary()}
  def add_block(%Block{} = block) do
    # TODO: catch error
    prev_block = get_block(block.header.prev_hash)
    prev_block_chain_state = chain_state(block.header.prev_hash)

    blocks_for_difficulty_calculation =
      get_blocks(block.header.prev_hash, Difficulty.get_number_of_blocks())

    try do
      new_chain_state =
        BlockValidation.calculate_and_validate_block!(
          block,
          prev_block,
          prev_block_chain_state,
          blocks_for_difficulty_calculation
        )

      add_validated_block(block, new_chain_state)
    catch
      {:error, message} ->
        Logger.error(fn -> "Failed to add block, #{message}" end)
        {:error, message}
    end
  end

  @spec add_validated_block(Block.t(), map()) :: :ok
  defp add_validated_block(%Block{} = block, chain_state) do
    GenServer.call(__MODULE__, {:add_validated_block, block, chain_state})
  end

  @spec chain_state(binary()) :: ChainState.account_chainstate()
  def chain_state(block_hash) do
    GenServer.call(__MODULE__, {:chain_state, block_hash})
  end

  @spec txs_index() :: txs_index()
  def txs_index() do
    GenServer.call(__MODULE__, :txs_index)
  end

  @spec registered_oracles() :: map()
  def registered_oracles() do
    GenServer.call(__MODULE__, :registered_oracles)
  end

  @spec oracle_interaction_objects() :: map()
  def oracle_interaction_objects() do
    GenServer.call(__MODULE__, :oracle_interaction_objects)
  end

  def chain_state() do
    top_block_chain_state()
  end

  @spec longest_blocks_chain() :: list(Block.t())
  def longest_blocks_chain() do
    get_blocks(top_block_hash(), top_height() + 1)
  end

  ## Server side

  def handle_call(:current_state, _from, state) do
    {:reply, state, state}
  end

  def handle_call(:top_block, _from, %{blocks_map: blocks_map, top_hash: top_hash} = state) do
    {:reply, blocks_map[top_hash], state}
  end

  def handle_call(:top_block_hash, _from, %{top_hash: top_hash} = state) do
    {:reply, top_hash, state}
  end

  def handle_call(
        :top_block_chain_state,
        _from,
        %{chain_states: chain_states, top_hash: top_hash} = state
      ) do
    {:reply, chain_states[top_hash], state}
  end

  def handle_call(:top_height, _from, %{top_height: top_height} = state) do
    {:reply, top_height, state}
  end

  def handle_call(
        :lowest_valid_nonce,
        _from,
        %{chain_states: chain_states, top_hash: top_hash} = state
      ) do
    {:ok, pubkey} = Keys.pubkey()
    chain_state = chain_states[top_hash]

    lowest_valid_nonce =
      if Map.has_key?(chain_state, pubkey) do
        chain_state[pubkey].nonce + 1
      else
        1
      end

    {:reply, lowest_valid_nonce, state}
  end

  def handle_call(
        {:get_block_from_memory_unsafe, block_hash},
        _from,
        %{blocks_map: blocks_map} = state
      ) do
    block = blocks_map[block_hash]

    if block != nil do
      {:reply, block, state}
    else
      {:reply, {:error, "Block not found"}, state}
    end
  end

  def handle_call(
        {:add_validated_block, %Block{} = new_block, new_chain_state},
        _from,
        %{
          blocks_map: blocks_map,
          chain_states: chain_states,
          txs_index: txs_index,
          registered_oracles: registered_oracles,
          oracle_interaction_objects: oracle_interaction_objects,
          top_height: top_height
        } = state
      ) do
    new_block_txs_index = calculate_block_acc_txs_info(new_block)
    new_txs_index = update_txs_index(txs_index, new_block_txs_index)

    Enum.each(new_block.txs, fn tx -> Pool.remove_transaction(tx) end)

    new_block_hash = BlockValidation.block_header_hash(new_block.header)
    updated_blocks_map = Map.put(blocks_map, new_block_hash, new_block)
    hundred_blocks_map = discard_blocks_from_memory(updated_blocks_map)

    updated_oracles =
      remove_expired_oracles(
        registered_oracles,
        new_block.header.height,
        new_txs_index,
        hundred_blocks_map
      )

    updated_oracle_interaction_objects =
      remove_expired_interaction_objects(
        oracle_interaction_objects,
        new_block.header.height,
        new_txs_index,
        hundred_blocks_map
      )

    new_registered_oracles = generate_registered_oracles_map(new_block, updated_oracles)

    new_oracle_interaction_objects =
      generate_oracle_interaction_objects_map(new_block, updated_oracle_interaction_objects)

    updated_chain_states = Map.put(chain_states, new_block_hash, new_chain_state)
    total_tokens = ChainState.calculate_total_tokens(new_chain_state)

    Logger.info(fn ->
      "Added block ##{new_block.header.height} with hash #{Header.bech32_encode(new_block_hash)}, total tokens: #{
        inspect(total_tokens)
      }"
    end)

    state_update1 = %{
      state
      | blocks_map: hundred_blocks_map,
        chain_states: updated_chain_states,
        txs_index: new_txs_index,
        registered_oracles: new_registered_oracles,
        oracle_interaction_objects: new_oracle_interaction_objects
    }

    if top_height < new_block.header.height do
      Persistence.batch_write(%{
        :chain_state => new_chain_state,
        :block => %{new_block_hash => new_block},
        :latest_block_info => %{
          "top_hash" => new_block_hash,
          "top_height" => new_block.header.height
        }
      })

      ## We send the block to others only if it extends the longest chain
      Peers.broadcast_block(new_block)
      # Broadcasting notifications for new block added to chain and new mined transaction
      Notify.broadcast_new_block_added_to_chain_and_new_mined_tx(new_block)

      {:reply, :ok,
       %{state_update1 | top_hash: new_block_hash, top_height: new_block.header.height}}
    else
      Persistence.batch_write(%{
        :chain_state => new_chain_state,
        :block => %{new_block_hash => new_block}
      })

      {:reply, :ok, state_update1}
    end
  end

  def handle_call({:chain_state, block_hash}, _from, %{chain_states: chain_states} = state) do
    {:reply, chain_states[block_hash], state}
  end

  def handle_call(:txs_index, _from, %{txs_index: txs_index} = state) do
    {:reply, txs_index, state}
  end

  def handle_call(:registered_oracles, _from, %{registered_oracles: registered_oracles} = state) do
    {:reply, registered_oracles, state}
  end

  def handle_call(
        :oracle_interaction_objects,
        _from,
        %{oracle_interaction_objects: oracle_interaction_objects} = state
      ) do
    {:reply, oracle_interaction_objects, state}
  end

  def handle_info(:timeout, state) do
    {top_hash, top_height} =
      case Persistence.get_latest_block_height_and_hash() do
        :not_found -> {state.top_hash, state.top_height}
        {:ok, latest_block} -> {latest_block.hash, latest_block.height}
      end

    chain_states =
      case Persistence.get_all_accounts_chain_states() do
        chain_states when chain_states == %{} -> state.chain_states
        chain_states -> %{top_hash => chain_states}
      end

    blocks_map =
      case Persistence.get_blocks(number_of_blocks_in_memory()) do
        blocks_map when blocks_map == %{} -> state.blocks_map
        blocks_map -> blocks_map
      end

    {:noreply,
     %{
       state
       | chain_states: chain_states,
         blocks_map: blocks_map,
         top_hash: top_hash,
         top_height: top_height
     }}
  end

  # Handle info coming from the asynchronous post we make to the oracle server.
  def handle_info(_, state) do
    {:noreply, state}
  end

  defp discard_blocks_from_memory(block_map) do
    if map_size(block_map) > number_of_blocks_in_memory() do
      [genesis_block, {_, b} | sorted_blocks] =
        Enum.sort(block_map, fn {_, b1}, {_, b2} ->
          b1.header.height < b2.header.height
        end)

      Logger.info("Block ##{b.header.height} has been removed from memory")
      Enum.into([genesis_block | sorted_blocks], %{})
    else
      block_map
    end
  end

  defp calculate_block_acc_txs_info(block) do
    block_hash = BlockValidation.block_header_hash(block.header)

    accounts =
      for tx <- block.txs do
        case tx.data do
          %SpendTx{} ->
            [tx.data.from_acc, tx.data.to_acc]

          %OracleRegistrationTxData{} ->
            tx.data.operator

          %OracleResponseTxData{} ->
            tx.data.operator

          %OracleQueryTxData{} ->
            tx.data.sender
        end
      end

    accounts_unique = accounts |> List.flatten() |> Enum.uniq() |> List.delete(nil)

    for account <- accounts_unique, into: %{} do
      acc_txs =
        Enum.filter(block.txs, fn tx ->
          case tx.data do
            %SpendTx{} ->
              tx.data.from_acc == account || tx.data.to_acc == account

            %OracleRegistrationTxData{} ->
              tx.data.operator == account

            %OracleResponseTxData{} ->
              tx.data.operator == account

            %OracleQueryTxData{} ->
              tx.data.sender == account
          end
        end)

      tx_hashes =
        Enum.map(acc_txs, fn tx ->
          SignedTx.hash_tx(tx)
        end)

      tx_tuples =
        Enum.map(tx_hashes, fn hash ->
          {block_hash, hash}
        end)

      {account, tx_tuples}
    end
  end

  defp get_tx_block_height_included(address, initial_hash, txs_index, blocks_map) do
    {block_hash, _tx_hash} =
      Enum.find(txs_index[address], fn {_block_hash, tx_hash} ->
        initial_hash == tx_hash
      end)

    block = Map.get(blocks_map, block_hash, Persistence.get_block_by_hash(block_hash))
    block.header.height
  end

  defp update_txs_index(prev_txs_index, new_txs_index) do
    Map.merge(prev_txs_index, new_txs_index, fn _, current_txs_index, new_txs_index ->
      current_txs_index ++ new_txs_index
    end)
  end

  defp generate_registered_oracles_map(block, current_registered_oracles_map) do
    Enum.reduce(block.txs, current_registered_oracles_map, fn tx, acc ->
      if match?(%OracleRegistrationTxData{}, tx.data) do
        Map.put_new(acc, tx.data.operator, %{tx: tx.data, initial_hash: SignedTx.hash_tx(tx)})
      else
        acc
      end
    end)
  end

  defp remove_expired_oracles(oracles, block_height, txs_index, blocks_map) do
    Enum.reduce(oracles, oracles, fn {address, %{tx: tx, initial_hash: initial_hash}}, acc ->
      tx_block_height_included =
        get_tx_block_height_included(tx.operator, initial_hash, txs_index, blocks_map)

      if Oracle.calculate_absolute_ttl(tx.ttl, tx_block_height_included) == block_height do
        Map.delete(acc, address)
      else
        acc
      end
    end)
  end

  defp generate_oracle_interaction_objects_map(block, current_oracle_interaction_objects_map) do
    Enum.reduce(block.txs, current_oracle_interaction_objects_map, fn tx, acc ->
      case tx.data do
        %OracleQueryTxData{} ->
          interaction_object_id = OracleQueryTxData.id(tx)

          Map.put(acc, interaction_object_id, %{
            query: tx.data,
            response: nil,
            query_initial_hash: SignedTx.hash_tx(tx),
            response_initial_hash: nil
          })

        %OracleResponseTxData{} ->
          if Map.has_key?(acc, tx.data.query_id) do
            interaction_object = Map.get(acc, tx.data.query_id)

            if interaction_object.response == nil do
              Map.put(acc, tx.data.query_id, %{
                interaction_object
                | response: tx.data,
                  response_initial_hash: SignedTx.hash_tx(tx)
              })
            else
              acc
            end
          else
            acc
          end

        _ ->
          acc
      end
    end)
  end

  defp remove_expired_interaction_objects(
         oracle_interaction_objects,
         block_height,
         txs_index,
         blocks_map
       ) do
    Enum.reduce(oracle_interaction_objects, oracle_interaction_objects, fn {query_tx_hash,
                                                                            %{
                                                                              query: query,
                                                                              response: response,
                                                                              query_initial_hash:
                                                                                query_initial_hash,
                                                                              response_initial_hash:
                                                                                response_initial_hash
                                                                            }},
                                                                           acc ->
      query_tx_block_height_included =
        get_tx_block_height_included(query.sender, query_initial_hash, txs_index, blocks_map)

      query_absolute_ttl =
        Oracle.calculate_absolute_ttl(query.query_ttl, query_tx_block_height_included)

      query_has_expired = query_absolute_ttl == block_height && response == nil

      response_has_expired =
        if response != nil do
          response_tx_block_height_included =
            get_tx_block_height_included(
              response.operator,
              response_initial_hash,
              txs_index,
              blocks_map
            )

          response_absolute_ttl =
            Oracle.calculate_absolute_ttl(query.query_ttl, response_tx_block_height_included)

          response_absolute_ttl == block_height
        else
          false
        end

      cond do
        query_has_expired ->
          Map.delete(acc, query_tx_hash)

        response_has_expired ->
          Map.delete(acc, query_tx_hash)

        true ->
          acc
      end
    end)
  end

  defp get_blocks(blocks_acc, next_block_hash, final_block_hash, count) do
    if next_block_hash != final_block_hash && count > 0 do
      case get_block(next_block_hash) do
        {:error, _} ->
          blocks_acc

        block ->
          updated_blocks_acc = [block | blocks_acc]
          prev_block_hash = block.header.prev_hash
          next_count = count - 1

          get_blocks(updated_blocks_acc, prev_block_hash, final_block_hash, next_count)
      end
    else
      blocks_acc
    end
  end

  defp number_of_blocks_in_memory() do
    Application.get_env(:aecore, :persistence)[:number_of_blocks_in_memory]
  end
end
