defmodule Aecore.Miner.Worker do
  use GenStateMachine, callback_mode: :state_functions

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Utils.Blockchain.Difficulty
  alias Aecore.Structures.Header
  alias Aecore.Structures.Block
  alias Aecore.Pow.Cuckoo
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.ChainState
  alias Aecore.Txs.Pool.Worker, as: Pool

  require Logger

  @coinbase_transaction_value 100
  @nonce_per_cycle 1

  def start_link(_args) do
    GenStateMachine.start_link(__MODULE__, {0, nil}, name: __MODULE__)
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
    GenStateMachine.call(__MODULE__, :start)
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
    Logger.info("[Miner] Mining resumed by user")
    GenStateMachine.cast(__MODULE__, :mine)
    {:next_state, :running, {0, nil}, [{:reply, from, :ok}]}
  end

  def idle({:call, from}, :suspend, data) do
    {:next_state, :idle, data, [{:reply, from, :not_started}]}
  end

  def idle({:call, from}, :get_state, _data) do
    {:keep_state_and_data, [{:reply, from, {:state, :idle}}]}
  end

  def idle({:call, from}, state, data) do
    Logger.info("[Miner] idle | call | state : #{inspect(state)}")
    {:next_state, :idle, data, [{:reply, from, :not_started}]}
  end

  def idle(:info, {:block_found, _}, {_, pid}) do
    Logger.info("[Miner] idle | info | block_found")
    stop_worker(pid)
    {:next_state, :idle, {0, nil}}
  end

  def idle(type, state, data) do
    Logger.info("[Miner] idle | type : #{inspect(_type)} | state: #{inspect(state)}")
    {:next_state, :idle, data}
  end

  ## Running ##
  def running(:cast, :mine, {start_nonce, _}) do
      case mine_next_block(start_nonce) do
        {:ok, nonce, pid} ->  {:next_state, :running, {nonce, pid}}
        {:error, _reason} ->  {:next_state, :idle, {0, nil}}
      end
  end

  def running({:call, from}, :get_state, {_, pid}) do
    {:keep_state_and_data, [{:reply, from, {:state, :running, pid}}]}
  end

  def running({:call, from}, :start, data) do
    {:next_state, :running, data, [{:reply, from, :already_started}]}
  end

  def running({:call, from}, :suspend, {_, pid}) do
    Logger.info("[Miner] Mining stopped by user")
    stop_worker(pid)
    {:next_state, :idle, {0, nil}, [{:reply, from, :ok}]}
  end

  def running({:call, from}, state, data) do
    Logger.info("[Miner] running | call | state : #{inspect(_state)}")
    {:next_state, :running, data, [{:reply, from, :not_suported}]}
  end

  def running(:info, {:block_found, nonce}, {_, pid}) do
    stop_worker(pid)
    GenStateMachine.cast(__MODULE__, :mine)
    {:next_state, :running, {nonce, nil}}
  end

  def running(:info, {:no_block_found, _}, {_, pid}) do
    Logger.info("[Miner] No block was found")
    stop_worker(pid)
    {:next_state, :idle, {0, nil}}
  end

  def running(type, state, {_, _pid} = data) do
    Logger.info("[Miner] running | type: #{inspect(type)} | state: #{inspect(state)}")
    {:next_state, :idle, data}
  end

  def get_coinbase_transaction(to_acc, total_fees) do
    tx_data = %TxData{
      from_acc: nil,
      to_acc: to_acc,
      value: @coinbase_transaction_value + total_fees,
      nonce: 0,
      fee: 0
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
  @spec mine_next_block(integer()) :: :ok | :error
  defp mine_next_block(start_nonce) do
    latest_block = Chain.latest_block()
    latest_block_hash = BlockValidation.block_header_hash(latest_block.header)
    chain_state = Chain.chain_state(latest_block_hash)

    # We take an extra block and then drop one at the head of the list
    # so the miner's blocks for difficulty calculation are the same as
    # the blocks in the add_block function
    blocks_for_difficulty_validation = if(latest_block.header.height == 0) do
      Chain.get_blocks(latest_block_hash, Difficulty.get_number_of_blocks())
    else
      Chain.get_blocks(latest_block_hash, Difficulty.get_number_of_blocks() + 1)
      |> Enum.drop(1)
    end

    previous_block = cond do
      latest_block == Block.genesis_block() -> nil
      true ->
        blocks = Chain.get_blocks(latest_block_hash, 2)
        Enum.at(blocks, 1)
    end

    try do
      BlockValidation.validate_block!(
        latest_block,
        previous_block,
        chain_state,
        blocks_for_difficulty_validation
      )

      blocks_for_difficulty_calculation = Chain.get_blocks(latest_block_hash, Difficulty.get_number_of_blocks())
      difficulty = Difficulty.calculate_next_difficulty(blocks_for_difficulty_calculation)

      txs_list = Map.values(Pool.get_pool())
      ordered_txs_list = Enum.sort(txs_list, fn (tx1, tx2) -> tx1.data.nonce < tx2.data.nonce end)
      valid_txs = BlockValidation.filter_invalid_transactions_chainstate(ordered_txs_list, chain_state)

      {_, pubkey} = Keys.pubkey()

      total_fees = calculate_total_fees(valid_txs)
      valid_txs = [get_coinbase_transaction(pubkey, total_fees) | valid_txs]
      root_hash = BlockValidation.calculate_root_hash(valid_txs)

      new_block_state = ChainState.calculate_block_state(valid_txs)
      new_chain_state = ChainState.calculate_chain_state(new_block_state, chain_state)
      chain_state_hash = ChainState.calculate_chain_state_hash(new_chain_state)

      latest_block_hash = BlockValidation.block_header_hash(latest_block.header)

      unmined_header =
        Header.create(
          latest_block.header.height + 1,
          latest_block_hash,
          root_hash,
          chain_state_hash,
          difficulty,
          0,
          #start from nonce 0, will be incremented in mining
          Block.current_block_version()
        )

      Logger.debug("start nonce #{start_nonce}. Final nonce = #{start_nonce + @nonce_per_cycle}")

      fun = fn(pid) ->
        res =
          case Cuckoo.generate(%{unmined_header | nonce: start_nonce + @nonce_per_cycle}) do
            {:ok, mined_header} ->
              block = %Block{header: mined_header, txs: valid_txs}
              Logger.info(
                fn ->
                  "Mined block ##{block.header.height}, difficulty target #{block.header.difficulty_target}, nonce #{
                  block.header.nonce
                  }" end
              )
              Chain.add_block(block)
              {:block_found, start_nonce + @nonce_per_cycle}
            {:error, message} ->
              Logger.error("[Miner] failed to generate block : #{inspect(message)}")
              {:no_block_found, 0}

          end
        send pid, res
      end

      pid = self()
      miner_pid = spawn fn() -> fun.(pid) end
      {:ok, start_nonce + @nonce_per_cycle, miner_pid}

    catch
      message ->
        Logger.error(fn -> "[Miner] Failed to mine block: #{Kernel.inspect(message)}" end)
      {:error, message}
    end

  end

  defp stop_worker(pid) when is_pid(pid), do: Process.exit(pid, :shutdown)
  defp stop_worker(_), do: :ok

end
