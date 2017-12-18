defmodule Aecore.Miner.Worker do
  @moduledoc """
  Handle the mining process.
  inspiration : https://github.com/aeternity/epoch/blob/master/apps/aecore/src/aec_conductor.erl
  """

  use GenServer

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

  require Logger

  @mersenne_prime 2147483647
  @coinbase_transaction_value 100

  def start_link(_args) do
    GenServer.start_link(__MODULE__, %{miner_state: :idle,
                                       nonce: 0,
                                       job: {},
                                       block_candidate: nil}, name: __MODULE__)
  end

  def stop(reason) do
    GenServer.stop(__MODULE__, reason)
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

  def init(state) do
    if Application.get_env(:aecore, :miner)[:resumed_by_default] do
      {:ok, state, 0}
    else
      {:ok, state}
    end
  end

  @spec resume() :: :ok
  def resume(), do: GenServer.call(__MODULE__, {:mining, :start})

  @spec suspend() :: :ok
  def suspend(), do: GenServer.call(__MODULE__, {:mining, :stop})

  @spec get_state() :: :running | :idle
  def get_state, do: GenServer.call(__MODULE__, :get_state)

  ## Mine single block and add it to the chain - Sync
  @spec mine_sync_block_to_chain() :: %Block{} | error :: term()
  def mine_sync_block_to_chain() do
    cblock = candidate()
    case mine_sync_block(cblock) do
      {:ok, new_block} -> Chain.add_block(new_block)
      {:error, _} = error -> error
    end
  end

  ## Mine single block without adding it to the chain - Sync
  @spec mine_sync_block(%Block{}) :: {:ok, %Block{}} | {:error, reason :: atom()}
  def mine_sync_block(%Block{} = cblock) do
    if GenServer.call(__MODULE__, :get_state) == :idle do
      mine_sync_block(Cuckoo.generate(cblock.header), cblock)
    else
      {:error, :miner_is_busy}
    end
  end

  defp mine_sync_block({:error, :no_solution}, %Block{} = cblock) do
    cheader = %{cblock.header | nonce: next_nonce(cblock.header.nonce)}
    cblock  = %{cblock | header: cheader}
    mine_sync_block(Cuckoo.generate(cheader), cblock)
  end
  defp mine_sync_block(%Header{} = mined_header, cblock) do
    {:ok, %{cblock | header: mined_header}}
  end

  ## Server side

  def handle_call({:mining, :stop}, _from, state) do
    {:reply, :ok, mining(%{state | miner_state: :idle, block_candidate: nil})}
  end
  def handle_call({:mining, :start}, _from, state) do
    {:reply, :ok, mining(%{state | miner_state: :running})}
  end
  def handle_call({:mining, {:start, :single_async_to_chain}}, _from, state) do
    {:reply, :ok, mining(%{state | miner_state: :running})}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state.miner_state, state}
  end

  def handle_call(any, _from, state) do
    Logger.info("[Miner] handle call any: #{inspect(any)}")
    {:reply, :ok, state}
  end

  def handle_cast(any, state) do
    Logger.info("[Miner] handle cast any: #{inspect(any)}")
    {:noreply, state}
  end

  def handle_info({:worker_reply, pid, result}, state) do
    {:noreply, handle_worker_reply(pid, result, state)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    Logger.info("[Miner] Mining was resumed by default")
    {:noreply, mining(%{state |
                        miner_state: :running,
                        block_candidate: candidate()})}
  end

  def handle_info(any, state) do
    Logger.info("[Miner] handle info any: #{inspect(any)}")
    {:noreply, state}
  end

  ## Private

  defp mining(%{miner_state: :running, job: job} = state)
  when job != {} do
    Logger.error("[Miner] Miner is still working")
    state
  end
  defp mining(%{miner_state: :running, block_candidate: nil} = state) do
    mining(%{state | block_candidate: candidate()})
  end
  defp mining(%{miner_state: :running, block_candidate: cblock} = state) do
    cheader = %{cblock.header | nonce: next_nonce(cblock.header.nonce)}
    cblock  = %{cblock | header: cheader}
    work = fn() -> Cuckoo.generate(cheader) end
    start_worker(work, %{state | block_candidate: cblock})
  end

  defp mining(%{miner_state: :idle, job: []} = state), do: state
  defp mining(%{miner_state: :idle} = state), do: stop_worker(state)

  defp start_worker(work, state) do
    server = self()
    {pid, ref} = spawn_monitor(fn() ->
      send(server, {:worker_reply, self(), work.()})
    end)

    %{state | job: {pid, ref}}
  end

  defp stop_worker(%{job: {}} = state), do: state
  defp stop_worker(%{job: job} = state) do
    %{state | job: cleanup_after_worker(job)}
  end

  defp cleanup_after_worker({pid, ref}) do
    Process.demonitor(ref, [:flush])
    Process.exit(pid, :shutdown)
    {}
  end

  defp handle_worker_reply(pid, reply, %{job: job} = state) do
    worker_reply(reply, %{state | job: cleanup_after_worker(job)})
  end

  defp worker_reply({:error, :no_solution}, state), do: mining(state)

  defp worker_reply(%{} = miner_header, %{block_candidate: cblock} = state) do
    Logger.info(
      fn ->
        "Mined block ##{cblock.header.height}, difficulty target #{cblock.header.difficulty_target}, nonce #{
        cblock.header.nonce
        }" end
    )
    cblock = %{cblock | header: miner_header}
    Chain.add_block(cblock)
    mining(%{state | block_candidate: nil})
  end

  def candidate() do
    latest_block = Chain.latest_block()
    latest_block_hash = BlockValidation.block_header_hash(latest_block.header)
    chain_state = Chain.chain_state(latest_block_hash)

    ## ------------------------------------------------------------------
    ## We take an extra block and then drop one at the head of the list
    ## so the miner's blocks for difficulty calculation are the same as
    ## the blocks in the add_block function
    ## -------------------------------------------------------------------

    blocks_for_difficulty_validation =
    if latest_block.header.height == 0 do
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

      txs_list = Map.values(Aecore.Txs.Pool.Worker.get_pool())
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
          0, #start from nonce 0, will be incremented in mining
          Block.current_block_version()
        )
      %Block{header: unmined_header, txs: valid_txs}
    catch
      error ->
        Logger.error("[Miner] Error while creating a block candidate #{inspect(error)}")
        error
    end

  end

  def calculate_total_fees(txs) do
    List.foldl(
      txs,
      0,
      fn (tx, acc) ->
        acc + tx.data.fee
      end
    )
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

  def next_nonce(@mersenne_prime), do: 0
  def next_nonce(nonce), do:  nonce + 1

end
