defmodule Aecore.Miner.Worker do

  use GenStateMachine, callback_mode: :state_functions

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Utils.Blockchain.BlockValidation
  alias Aecore.Utils.Blockchain.Difficulty
  alias Aecore.Block.Headers
  alias Aecore.Block.Blocks
  alias Aecore.Pow.Hashcash
  alias Aecore.Keys.Worker, as: Keys
  alias Aecore.Structures.TxData
  alias Aecore.Structures.SignedTx

  @coinbase_transaction_value 100

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
   def idle({:call, from}, :start , data) do
     IO.puts "Mining resuming by user"
     GenStateMachine.cast(__MODULE__, :mine)
     {:next_state, :running, data, [{:reply, from, :ok}]}
   end

   def idle({:call, from}, :suspend , data) do
     {:next_state, :idle, data, [{:reply, from, :not_started}]}
   end

   def idle({:call, from}, :get_state, data) do
     {:keep_state_and_data, [{:reply, from, {:state, :idle}}]}
   end

   def idle({:call, from}, _ , data) do
     {:next_state, :idle, data, [{:reply, from, :not_started}]}
   end

   def idle(type, state , data) do
     {:next_state, :idle, data}
   end

   ## Running ##
   def running(:cast, :mine, data) do
     mine_next_block([])
     GenStateMachine.cast(__MODULE__,:mine)
     {:next_state, :running, data}
   end

   def running({:call, from}, :get_state, data) do
     {:keep_state_and_data, [{:reply, from, {:state, :running}}]}
   end

   def running({:call, from}, :start, data) do
     {:next_state, :running, data, [{:reply, from, :already_started}]}
   end

   def running({:call, from}, :suspend, data) do
     IO.puts "Mined stop by user"
     {:next_state, :idle, data, [{:reply, from, :ok}]}
   end

   def running({:call, from}, _, data) do
     {:next_state, :running, data, [{:reply, from, :not_suported}]}
   end

   def running(_, _, data) do
     {:next_state, :idle, data}
   end

   def get_coinbase_transaction() do
     {_, pubkey} = Keys.pubkey()
     tx_data = %{TxData.create |
                 :to_acc => pubkey,
                 :value => @coinbase_transaction_value,
                 :nonce => Enum.random(0..1000000000000)}
     %{SignedTx.create | data: tx_data}
  end

  def coinbase_transaction_value, do: @coinbase_transaction_value

  ## Internal
  @spec mine_next_block(list()) :: :ok
  defp mine_next_block(txs) do
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
    valid_txs = [get_coinbase_transaction() | valid_txs]
    root_hash = BlockValidation.calculate_root_hash(valid_txs)

    latest_block_hash = BlockValidation.block_header_hash(latest_block.header)
    difficulty = Difficulty.calculate_next_difficulty(chain)

    unmined_header = Headers.new(latest_block.header.height + 1, latest_block_hash, root_hash, difficulty, 0, 1)
    {:ok, mined_header} = Hashcash.generate(unmined_header)
    {:ok, block} = Blocks.new(mined_header, valid_txs)
    IO.inspect("block: #{block.header.height} difficulty: #{block.header.difficulty_target}")
    Chain.add_block(block)
  end

end
