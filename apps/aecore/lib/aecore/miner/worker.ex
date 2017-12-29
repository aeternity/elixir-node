defmodule Aecore.Miner.Worker do
  use GenStateMachine, callback_mode: :state_functions

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.BlockValidation
  alias Aecore.Chain.Difficulty
  alias Aecore.Structures.Header
  alias Aecore.Structures.Block
  alias Aecore.Pow.Cuckoo
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.ChainState
  alias Aecore.Txs.Pool.Worker, as: Pool
  alias Aeutil.Bits
  alias Aecore.Peers.Worker, as: Peers

  require Logger

  @coinbase_transaction_value 100
  @nonce_per_cycle 1

  def start_link(_args) do
    GenStateMachine.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def child_spec(arg) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [arg]},
      restart: :permanent,
      shutdown: 5000,
      type: :worker
    }
  end

  def resume() do
    if Peers.is_chain_synced? do
      GenStateMachine.call(__MODULE__, :start)
    else
      Logger.error("Can't start miner, chain not yet synced")
    end
  end

  def suspend() do
    GenStateMachine.call(__MODULE__, :suspend)
  end

  def init(data) do
    GenStateMachine.cast(__MODULE__, :idle)
    {:ok, :running, data}
  end

  def get_state() do
    GenStateMachine.call(__MODULE__, :get_state)
  end

  ## Idle ##
  def idle({:call, from}, :start, _data) do
    Logger.info("Mining resumed by user")
    GenStateMachine.cast(__MODULE__, :mine)
    {:next_state, :running, 0, [{:reply, from, :ok}]}
  end

  def idle({:call, from}, :suspend, data) do
    {:next_state, :idle, data, [{:reply, from, :not_started}]}
  end

  def idle({:call, from}, :get_state, _data) do
    {:keep_state_and_data, [{:reply, from, {:state, :idle}}]}
  end

  def idle({:call, from}, _, data) do
    {:next_state, :idle, data, [{:reply, from, :not_started}]}
  end

  def idle(_type, _state, data) do
    {:next_state, :idle, data}
  end

  ## Running ##
  def running(:cast, :mine, start_nonce) do
    {status, next_nonce} = mine_next_block(start_nonce)
    case status do
      :error ->
        Logger.info("Mining stopped by error")
        {:next_state, :idle, 0}
      _ ->
        GenStateMachine.cast(__MODULE__, :mine)
        {:next_state, :running, next_nonce}
    end
  end

  def running({:call, from}, :get_state, _data) do
    {:keep_state_and_data, [{:reply, from, {:state, :running}}]}
  end

  def running({:call, from}, :start, data) do
    {:next_state, :running, data, [{:reply, from, :already_started}]}
  end

  def running({:call, from}, :suspend, data) do
    Logger.info("Mining stopped by user")
    {:next_state, :idle, data, [{:reply, from, :ok}]}
  end

  def running({:call, from}, _, data) do
    {:next_state, :running, data, [{:reply, from, :not_suported}]}
  end

  def running(_, _, data) do
    {:next_state, :idle, data}
  end

  def set_tx_bytes_per_token(bytes) do
    Application.put_env(:aecore, :tx_data, miner_fee_bytes_per_token: bytes)
  end

  def get_coinbase_transaction(to_acc, total_fees, lock_time_block) do
    tx_data = %TxData{
      from_acc: nil,
      to_acc: to_acc,
      value: @coinbase_transaction_value + total_fees,
      nonce: 0,
      fee: 0,
      lock_time_block: lock_time_block
    }

    %SignedTx{data: tx_data, signature: nil}
  end

  def coinbase_transaction_value, do: @coinbase_transaction_value

  def calculate_total_fees(txs) do
    List.foldl(
      txs,
      0,
      fn (tx, acc) ->
        acc + tx.data.fee
      end
    )
  end

  ## Internal
  @spec mine_next_block(integer) :: :ok | :error
  defp mine_next_block(start_nonce) do
    top_block = Chain.top_block()
    top_block_hash = BlockValidation.block_header_hash(top_block.header)
    chain_state = Chain.chain_state(top_block_hash)

    # We take an extra block and then drop one at the head of the list
    # so the miner's blocks for difficulty calculation are the same as
    # the blocks in the add_block function
    blocks_for_difficulty_validation = if top_block.header.height == 0 do
      [top_block]
    else
      top_block_hash
      |> Chain.get_blocks(Difficulty.get_number_of_blocks() + 1)
      |> Enum.drop(1)
    end

    previous_block = unless top_block == Block.genesis_block() do
      Chain.get_block(top_block.header.prev_hash)
    else 
      nil
    end

    try do
      BlockValidation.validate_block!(
        top_block,
        previous_block,
        chain_state,
        blocks_for_difficulty_validation
      )

      blocks_for_difficulty_calculation = Chain.get_blocks(top_block_hash, Difficulty.get_number_of_blocks())
      difficulty = Difficulty.calculate_next_difficulty(blocks_for_difficulty_calculation)

      txs_list = Map.values(Pool.get_pool())
      ordered_txs_list = Enum.sort(txs_list, fn (tx1, tx2) -> tx1.data.nonce < tx2.data.nonce end)
      valid_txs_by_chainstate = BlockValidation.filter_invalid_transactions_chainstate(ordered_txs_list, chain_state)
      valid_txs_by_fee = filter_transactions_by_fee(valid_txs_by_chainstate)

      {_, pubkey} = Keys.pubkey()

      total_fees = calculate_total_fees(valid_txs_by_fee)
      valid_txs = [get_coinbase_transaction(pubkey, total_fees,
                                            top_block.header.height + 1 +
                                            Application.get_env(:aecore, :tx_data)[:lock_time_coinbase]) | valid_txs_by_fee]
      root_hash = BlockValidation.calculate_root_hash(valid_txs)

      new_block_state =
        ChainState.calculate_block_state(valid_txs, top_block.header.height)
      new_chain_state = ChainState.calculate_chain_state(new_block_state, chain_state)
      new_chain_state_locked_amounts =
        ChainState.update_chain_state_locked(new_chain_state, top_block.header.height + 1)
      chain_state_hash = ChainState.calculate_chain_state_hash(new_chain_state_locked_amounts)

      top_block_hash = BlockValidation.block_header_hash(top_block.header)

      unmined_header =
        Header.create(
          top_block.header.height + 1,
          top_block_hash,
          root_hash,
          chain_state_hash,
          difficulty,
          0,
          #start from nonce 0, will be incremented in mining
          Block.current_block_version()
        )

      Logger.debug(fn -> "start nonce #{start_nonce}. Final nonce = #{start_nonce + @nonce_per_cycle}" end)

      case Cuckoo.generate(%{unmined_header | nonce: start_nonce + @nonce_per_cycle}) do
        {:ok, mined_header} ->
          block = %Block{header: mined_header, txs: valid_txs}
          Logger.info(fn ->
              "Mined block ##{block.header.height}, difficulty target #{block.header.difficulty_target}, nonce #{block.header.nonce}"
          end)
          Chain.add_block(block)
          {:block_found, 0}

        {:error, _message} ->
          {:no_block_found, start_nonce + @nonce_per_cycle}
      end

    catch
      message ->
        Logger.error(fn -> "Failed to mine block: #{Kernel.inspect(message)}" end)
        {:error, message}
    end
  end

  defp filter_transactions_by_fee(txs) do
    Enum.filter(txs, fn(tx) ->
      tx_size_bits =
        tx |> :erlang.term_to_binary() |> Bits.extract() |> Enum.count()
      tx_size_bytes = tx_size_bits / 8

      tx.data.fee >= Float.floor(tx_size_bytes /
                                  Application.get_env(:aecore, :tx_data)[:miner_fee_bytes_per_token])
    end)
  end
end
