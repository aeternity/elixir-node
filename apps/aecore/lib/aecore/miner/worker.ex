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

  def start_link() do
    GenStateMachine.start_link(__MODULE__, %{}, name: __MODULE__)
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
    IO.puts("Mining resuming by user")
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
    {_, next_nonce} = mine_next_block(start_nonce)
    GenStateMachine.cast(__MODULE__, :mine)
    {:next_state, :running, next_nonce}
  end

  def running({:call, from}, :get_state, _data) do
    {:keep_state_and_data, [{:reply, from, {:state, :running}}]}
  end

  def running({:call, from}, :start, data) do
    {:next_state, :running, data, [{:reply, from, :already_started}]}
  end

  def running({:call, from}, :suspend, data) do
    IO.puts("Mined stop by user")
    {:next_state, :idle, data, [{:reply, from, :ok}]}
  end

  def running({:call, from}, _, data) do
    {:next_state, :running, data, [{:reply, from, :not_suported}]}
  end

  def running(_, _, data) do
    {:next_state, :idle, data}
  end

  def get_coinbase_transaction(to_acc) do
    tx_data = %TxData{
      from_acc: nil,
      to_acc: to_acc,
      value: @coinbase_transaction_value,
      nonce: 0
    }

    %SignedTx{data: tx_data, signature: nil}
  end

  def coinbase_transaction_value, do: @coinbase_transaction_value

  ## Internal
  @spec mine_next_block(integer()) :: :ok | :error
  defp mine_next_block(start_nonce) do
    latest_block = Chain.latest_block()
    latest_block_hash = BlockValidation.block_header_hash(latest_block.header)
    chain_state = Chain.chain_state(latest_block_hash)

    txs_list = Map.values(Pool.get_pool())
    ordered_txs_list = Enum.sort(txs_list, fn(tx1, tx2) -> tx1.data.nonce < tx2.data.nonce end)

    blocks_for_difficulty_calculation = Chain.get_blocks(latest_block_hash, Difficulty.get_number_of_blocks())
    previous_block = cond do
      latest_block == Block.genesis_block() -> nil
      true ->
        blocks = Chain.get_blocks(latest_block_hash, 2)
        Enum.at(blocks, 1)
    end

    BlockValidation.validate_block!(latest_block, previous_block, chain_state)

    valid_txs = BlockValidation.filter_invalid_transactions_chainstate(ordered_txs_list, chain_state)
    {_, pubkey} = Keys.pubkey()
    valid_txs = [get_coinbase_transaction(pubkey) | valid_txs]
    root_hash = BlockValidation.calculate_root_hash(valid_txs)

    new_block_state = ChainState.calculate_block_state(valid_txs)
    new_chain_state = ChainState.calculate_chain_state(new_block_state, chain_state)
    chain_state_hash = ChainState.calculate_chain_state_hash(new_chain_state)

    latest_block_hash = BlockValidation.block_header_hash(latest_block.header)

    difficulty = Difficulty.calculate_next_difficulty(blocks_for_difficulty_calculation)

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
    Logger.debug("start nonce #{start_nonce}. Final nonce = #{start_nonce + @nonce_per_cycle}")
    case Cuckoo.generate(%{unmined_header
                           | nonce: start_nonce + @nonce_per_cycle}) do
      {:ok, mined_header} ->
        block = %Block{header: mined_header, txs: valid_txs}
        Chain.add_block(block)
        Logger.info(fn ->
          "Mined block ##{block.header.height}, difficulty target #{block.header.difficulty_target}, nonce #{block.header.nonce}"
          end)
        {:block_found, 0}

      {:error, _message} ->
        {:no_block_found, start_nonce + @nonce_per_cycle}
    end
  end
end
