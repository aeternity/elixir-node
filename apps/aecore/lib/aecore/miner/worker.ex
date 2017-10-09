defmodule Aecore.Miner.Worker do

  use GenStateMachine, callback_mode: :state_functions

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.ChainState
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Utils.Blockchain.Difficulty
  alias Aecore.Block.Headers
  alias Aecore.Block.Blocks
  alias Aecore.Pow.Hashcash

  def start_link() do
    GenStateMachine.start_link(__MODULE__, {:off, 0}, name: __MODULE__)
  end

  def resume() do
    GenStateMachine.call(__MODULE__,:start)
  end

  def suspend() do
    GenStateMachine.call(__MODULE__,:suspend)
  end

  def init(_) do
    GenStateMachine.cast(__MODULE__,:mine)
    {:ok, :running, 0}
  end

  ## Idle ##
  def idle({:call, from}, start , data) do
    IO.inspect "Mining resuming by user"
    GenStateMachine.cast(__MODULE__,:mine)
    {:next_state, :running, data, [{:reply, from, :ok}]}
  end

  def idle({:call, from}, suspend , data) do
    {:next_state, :idle, data, [{:reply, from, :not_started}]}
  end

  def idle({:call, from}, _ , data) do
    {:next_state, :idle, data, [{:reply, from, :not_started}]}
  end

  def idle(type, state , data) do
    IO.inspect type
    IO.inspect state
    {:next_state, :idle, data}
  end
  ## Running ##
  def running(:cast, :mine, data) do
    IO.inspect "begin new block"
    mine([])
    GenStateMachine.cast(__MODULE__,:mine)
    {:next_state, :running, data + 1}
  end

  def running({:call, from}, :start, data) do
    {:next_state, :running, data, [{:reply, from, :already_started}]}
  end

  def running({:call, from}, :suspend, data) do
    IO.inspect "report suspending"
    {:next_state, :idle, data, [{:reply, from, :ok}]}
  end

  def running({:call, from}, _, data) do
    {:next_state, :running, data, [{:reply, from, :not_suported}]}
  end

  def running(_, _, data) do
    {:next_state, :idle, data}
  end

  ## Internal
  @spec mine(list()) :: :ok
  defp mine(txs) do
    chain = Chain.all_blocks()
    chain_state = Chain.chain_state()
    #validate latest block if the chain has more than the genesis block
    latest_block = if(length(chain) == 1) do
      [latest_block | _] = chain
      latest_block
    else
      [latest_block, previous_block | _] = chain
      BlockValidation.validate_block!(latest_block, previous_block)
      latest_block
    end

    valid_txs = BlockValidation.filter_invalid_transactions(txs)
    root_hash = BlockValidation.calculate_root_hash(valid_txs)

    new_block_state = ChainState.calculate_block_state(valid_txs)
    new_chain_state =
      ChainState.calculate_chain_state(new_block_state, chain_state)

    chain_state_hash = ChainState.calculate_chain_state_hash(new_chain_state)

    latest_block_hash = BlockValidation.block_header_hash(latest_block.header)
    difficulty = Difficulty.calculate_next_difficulty(chain)

    unmined_header = Headers.new(latest_block.header.height + 1,
      latest_block_hash, root_hash, chain_state_hash, difficulty, 0, 1)
    {:ok, mined_header} = Hashcash.generate(unmined_header)
    {:ok, block} = Blocks.new(mined_header, valid_txs)
    Chain.add_block(block)
    :timer.sleep(2000)
    IO.inspect "2 sec work done !"
  end

end
