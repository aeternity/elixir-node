defmodule Aecore.Miner.Worker do
  @moduledoc """
  Module for the miner
  """

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Utils.Blockchain.Difficulty
  alias Aecore.Block.Headers
  alias Aecore.Block.Blocks
  alias Aecore.Pow.Hashcash

  use GenStateMachine

  def start_link() do
    GenStateMachine.start_link(__MODULE__, %{}, name: __MODULE__)
  end

  def resume() do
    GenStateMachine.cast(__MODULE__, :mine)
  end

  def suspend() do
    GenStateMachine.call(__MODULE__, :suspend)
  end

  # Server (callbacks)

  def init(data) do
    IO.inspect "initial start of the Miner"
    resume()
    {:ok, :running, data}
  end

  @spec mine_next_block(list()) :: :ok
  def mine_next_block(txs) do
    chain = Chain.all_blocks()

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

    latest_block_hash = BlockValidation.block_header_hash(latest_block.header)
    difficulty = Difficulty.calculate_next_difficulty(chain)

    unmined_header = Headers.new(latest_block.header.height + 1, latest_block_hash, root_hash, difficulty, 0, 1)
    {:ok, mined_header} = Hashcash.generate(unmined_header)
    {:ok, block} = Blocks.new(mined_header, valid_txs)
    Chain.add_block(block)
  end

  def handle_event(:cast, :mine, :idle, data) do
    IO.inspect "[cast] to mine from idle"
    mine_next_block([])
    resume()
    {:next_state, :running, data}
  end

  def handle_event(:cast, :mine, :running, data) do
    IO.inspect "[cast] to mine from running"
    mine_next_block([])
    resume()
    {:next_state, :running, data}
  end

  def handle_event({:call, from}, :suspend, :running, data) do
    IO.inspect "[call] to suspend from running"
    {:next_state, :idle, data, [{:reply, from, :ok}]}
  end

  def handle_event(event_type, event_content, state, data) do
    # Call the default implementation from GenStateMachine
    IO.inspect ".......Any............"
    super(event_type, event_content, state, data)
  end

end
