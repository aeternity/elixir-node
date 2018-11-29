defmodule Aecore.Miner.Worker do
  @moduledoc """
  Handles the mining process.
  inspiration : https://github.com/aeternity/epoch/blob/master/apps/aecore/src/aec_conductor.erl
  """

  use GenServer

  alias Aecore.Chain.{
    MicroBlock,
    MicroHeader,
    KeyBlock,
    KeyHeader,
    BlockValidation,
    Chainstate,
    Target,
    Identifier
  }

  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Contract.{CallStateTree, Contract}
  alias Aecore.Contract.Tx.{ContractCreateTx, ContractCallTx}
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Keys
  alias Aecore.Oracle.Oracle
  alias Aecore.Pow.Pow
  alias Aecore.Tx.Pool.Worker, as: Pool
  alias Aecore.Tx.{DataTx, SignedTx}
  alias Aecore.Util.Header
  alias Aeutil.Environment

  require Logger

  @mersenne_prime 2_147_483_647

  @minimum_distance_from_key_block 1

  @spec start_link(any()) :: :ignore | {:error, any()} | {:ok, pid()}
  def start_link(_args) do
    :ok = Application.ensure_started(:erlexec)

    GenServer.start_link(
      __MODULE__,
      %{miner_state: :idle, nonce: 0, job: {}, block_candidate: nil},
      name: __MODULE__
    )
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
  def resume do
    GenServer.call(__MODULE__, {:mining, :start})
  end

  @spec suspend() :: :ok
  def suspend, do: GenServer.call(__MODULE__, {:mining, :stop})

  @spec get_state() :: :running | :idle
  def get_state, do: GenServer.call(__MODULE__, :get_state)

  # Mine single block and add it to the chain - Sync
  @spec mine_sync_block_to_chain() :: KeyBlock.t() | error :: term()
  def mine_sync_block_to_chain do
    cblock = candidate()
    loop_micro_block = false

    case mine_sync_block(cblock) do
      {:ok, new_block} -> Chain.add_block(new_block, loop_micro_block)
      {:error, _} = error -> error
    end
  end

  # Mine single block without adding it to the chain - Sync
  @spec mine_sync_block(KeyBlock.t()) :: {:ok, KeyBlock.t()} | {:error, reason :: atom()}
  def mine_sync_block(%KeyBlock{header: %KeyHeader{} = header} = cblock) do
    cond do
      GenServer.call(__MODULE__, :get_state) != :idle ->
        {:error, :miner_is_busy}

      (pow = Pow.generate(header)) != {:error, :miner_was_stopped} ->
        mine_sync_block(pow, cblock)

      true ->
        # When the miner crashed on the first run we can be sure that this is not a random crash
        {:error, :miner_crashed}
    end
  end

  defp mine_sync_block(
         {:error, :no_solution},
         %KeyBlock{header: %KeyHeader{nonce: nonce} = header} = cblock
       ) do
    cheader = %{header | nonce: next_nonce(nonce)}
    cblock = %{cblock | header: cheader}
    mine_sync_block(Pow.generate(cheader), cblock)
  end

  defp mine_sync_block(
         {:error, :miner_was_stopped},
         %KeyBlock{header: %KeyHeader{} = cheader} = cblock
       ) do
    case Pow.generate(cheader) do
      {:error, :miner_was_stopped} ->
        {:error, :miner_crashed}

      pow ->
        mine_sync_block(pow, cblock)
    end
  end

  defp mine_sync_block({:ok, %KeyHeader{} = mined_header}, cblock) do
    {:ok, %{cblock | header: mined_header}}
  end

  # Server side

  def handle_call({:mining, :stop}, _from, state) do
    Logger.info("#{__MODULE__}: stopping miner")
    {:reply, :ok, mining(%{state | miner_state: :idle, block_candidate: nil})}
  end

  def handle_call({:mining, :start}, _from, state) do
    Logger.info("#{__MODULE__}: starting miner")
    {:reply, :ok, mining(%{state | miner_state: :running})}
  end

  def handle_call({:mining, {:start, :single_async_to_chain}}, _from, state) do
    {:reply, :ok, mining(%{state | miner_state: :running})}
  end

  def handle_call(:get_state, _from, state) do
    {:reply, state.miner_state, state}
  end

  def handle_call(any, _from, state) do
    Logger.info("#{__MODULE__}: handle call any: #{inspect(any)}")
    {:reply, :ok, state}
  end

  def handle_cast(any, state) do
    Logger.info("#{__MODULE__}: handle cast any: #{inspect(any)}")
    {:noreply, state}
  end

  def handle_info({:worker_reply, pid, result}, state) do
    {:noreply, handle_worker_reply(pid, result, state)}
  end

  def handle_info({:DOWN, _ref, :process, _pid, :normal}, state) do
    {:noreply, state}
  end

  def handle_info(:timeout, state) do
    Logger.info("#{__MODULE__}: Mining was resumed by default")
    {:noreply, mining(%{state | miner_state: :running, block_candidate: candidate()})}
  end

  def handle_info(any, state) do
    Logger.info("#{__MODULE__}: handle info any: #{inspect(any)}")
    {:noreply, state}
  end

  # Private

  defp mining(%{miner_state: :running, job: job} = state)
       when job != {} do
    Logger.error("#{__MODULE__}: Miner is still working")
    state
  end

  defp mining(%{miner_state: :running, block_candidate: nil} = state) do
    mining(%{state | block_candidate: candidate()})
  end

  defp mining(%{miner_state: :running, block_candidate: cblock} = state) do
    nonce = next_nonce(cblock.header.nonce)

    cblock =
      case rem(nonce, new_candidate_nonce_count()) do
        0 -> candidate()
        _ -> cblock
      end

    cheader = %{cblock.header | nonce: nonce}
    cblock_with_header = %{cblock | header: cheader}
    work = fn -> Pow.generate(cheader) end
    start_worker(work, %{state | block_candidate: cblock_with_header})
  end

  defp mining(%{miner_state: :idle, job: []} = state), do: state
  defp mining(%{miner_state: :idle} = state), do: stop_worker(state)

  defp start_worker(work, state) do
    server = self()

    {pid, ref} =
      spawn_monitor(fn ->
        send(server, {:worker_reply, self(), work.()})
        :ok
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

  defp handle_worker_reply(_pid, reply, %{job: job} = state) do
    worker_reply(reply, %{state | job: cleanup_after_worker(job)})
  end

  defp worker_reply({:error, :no_solution}, state), do: mining(state |> Map.delete(:retries))

  defp worker_reply({:error, :miner_was_stopped}, %{block_candidate: nil} = state) do
    throw({:error, "Miner crashed, #{inspect(state)}"})
  end

  defp worker_reply({:error, :miner_was_stopped}, %{retries: 10} = state) do
    throw({:error, "Miner crashed, #{inspect(state)}"})
  end

  defp worker_reply({:error, :miner_was_stopped}, %{block_candidate: block} = state) do
    cblock = %KeyBlock{
      block
      | header: %KeyHeader{block.header | nonce: prev_nonce(block.header.nonce)}
    }

    retries = if Map.has_key?(state, :retries), do: state.retries + 1, else: 1
    nstate = Map.put(state, :retries, retries)

    mining(%{nstate | block_candidate: cblock})
  end

  defp worker_reply({:ok, %KeyHeader{} = miner_header}, %{block_candidate: cblock} = state) do
    Logger.info(fn -> "#{__MODULE__}: Mined block ##{cblock.header.height},
        difficulty target #{cblock.header.target},
        nonce #{cblock.header.nonce}" end)

    cblock = %{cblock | header: miner_header}
    loop_micro_blocks = true
    Chain.add_block(cblock, loop_micro_blocks)
    mining(%{state | block_candidate: nil})
  end

  @spec candidate() :: KeyBlock.t()
  def candidate do
    top_block = Chain.top_block()

    top_block_hash = Header.hash(top_block.header)
    top_key_block_hash = Header.top_key_block_hash(top_block.header)
    {:ok, chain_state} = Chain.chain_state(top_block_hash)

    blocks_for_target_calculation =
      Chain.get_key_blocks(
        top_key_block_hash,
        GovernanceConstants.number_of_blocks_for_target_recalculation()
      )

    timestamp = System.system_time(:milliseconds)

    target = Target.calculate_next_target(timestamp, blocks_for_target_calculation)

    {miner_pubkey, _} = Keys.keypair(:sign)

    create_block(
      top_block,
      chain_state,
      target,
      timestamp,
      miner_pubkey,
      miner_pubkey
    )
  end

  @spec generate_and_add_micro_block(
          Chainstate.t(),
          binary(),
          binary(),
          non_neg_integer(),
          boolean()
        ) :: :ok | {:error, String.t()}
  def generate_and_add_micro_block(
        chain_state,
        prev_hash,
        prev_key_hash,
        last_time,
        loop_micro_blocks
      ) do
    txs_list = get_pool_values()
    ordered_txs_list = Enum.sort(txs_list, fn tx1, tx2 -> tx1.data.nonce < tx2.data.nonce end)

    candidate_height = Chain.top_height()

    valid_txs_by_chainstate =
      Chainstate.get_valid_txs(ordered_txs_list, chain_state, candidate_height)

    valid_txs_by_fee =
      filter_transactions_by_fee_and_ttl(valid_txs_by_chainstate, chain_state, candidate_height)

    txs_hash = BlockValidation.calculate_txs_hash(valid_txs_by_fee)

    {:ok, new_chain_state} =
      Chainstate.calculate_and_validate_chain_state(
        %MicroBlock{txs: valid_txs_by_fee},
        chain_state,
        candidate_height
      )

    root_hash = Chainstate.calculate_root_hash(new_chain_state)
    current_time = System.system_time(:milliseconds)

    # if the previous block is a key block - the time should just be higher,
    # if it's a micro block - atleast 3 seconds higher
    minimum_distance =
      if prev_hash == prev_key_hash do
        @minimum_distance_from_key_block
      else
        GovernanceConstants.micro_block_distance()
      end

    time = max(current_time, last_time + minimum_distance)

    header = %MicroHeader{
      height: candidate_height,
      pof_hash: nil,
      prev_hash: prev_hash,
      prev_key_hash: prev_key_hash,
      txs_hash: txs_hash,
      root_hash: root_hash,
      time: time,
      version: GovernanceConstants.protocol_version(),
      signature: <<0::512>>
    }

    signature = header |> MicroHeader.encode_to_binary() |> Keys.sign()

    header_with_signature = %{header | signature: signature}

    block = %MicroBlock{header: header_with_signature, txs: valid_txs_by_fee}

    :timer.sleep(minimum_distance)

    Chain.add_block(block, loop_micro_blocks)
  end

  @spec calculate_miner_reward(list(SignedTx.t()), Chainstate.t()) :: non_neg_integer()
  def calculate_miner_reward(txs, chainstate) do
    List.foldl(txs, 0, fn %SignedTx{
                            data: %DataTx{
                              payload: payload,
                              fee: fee,
                              nonce: nonce,
                              senders: senders
                            }
                          },
                          accumulated_miner_reward ->
      main_sender = List.first(senders)

      gas_used =
        case payload do
          %ContractCreateTx{gas_price: gas_price} ->
            contract_id = Contract.create_contract_id(main_sender.value, nonce)

            call_gas_used =
              CallStateTree.get_call_gas_used(
                chainstate.calls,
                contract_id,
                main_sender.value,
                nonce
              )

            call_gas_used * gas_price

          %ContractCallTx{contract: %Identifier{value: contract_id}, gas_price: gas_price} ->
            call_gas_used =
              CallStateTree.get_call_gas_used(
                chainstate.calls,
                contract_id,
                main_sender.value,
                nonce
              )

            call_gas_used * gas_price

          _ ->
            0
        end

      accumulated_miner_reward + fee + gas_used
    end)
  end

  # Internal

  defp get_pool_values do
    pool_values = Map.values(Pool.get_pool())
    max_txs_for_block = Application.get_env(:aecore, :tx_data)[:max_txs_per_block]

    if length(pool_values) < max_txs_for_block do
      pool_values
    else
      Enum.slice(pool_values, 0..(max_txs_for_block - 1))
    end
  end

  defp filter_transactions_by_fee_and_ttl(txs, chain_state, block_height) do
    Enum.filter(txs, fn %SignedTx{data: %DataTx{type: type} = data_tx} = tx ->
      ttl_valid = Oracle.tx_ttl_is_valid?(tx, block_height)

      minimum_fee_met =
        type.is_minimum_fee_met?(
          data_tx,
          Map.get(chain_state, type.get_chain_state_name()),
          block_height
        )

      ttl_valid && minimum_fee_met
    end)
  end

  defp create_block(top_block, chain_state, target, timestamp, miner_pubkey, beneficiary) do
    {:ok, new_chain_state} =
      Chainstate.calculate_and_validate_chain_state(
        top_block,
        chain_state,
        top_block.header.height + 1
      )

    root_hash = Chainstate.calculate_root_hash(new_chain_state)

    top_block_hash = Header.hash(top_block.header)

    top_key_block_hash = Header.top_key_block_hash(top_block.header)

    # start from nonce 0, will be incremented in mining
    unmined_header = %KeyHeader{
      height: top_block.header.height + 1,
      prev_hash: top_block_hash,
      prev_key_hash: top_key_block_hash,
      root_hash: root_hash,
      target: target,
      nonce: 0,
      time: timestamp,
      miner: miner_pubkey,
      beneficiary: beneficiary,
      version: GovernanceConstants.protocol_version()
    }

    %KeyBlock{header: unmined_header}
  end

  def next_nonce(@mersenne_prime), do: 0
  def next_nonce(nonce), do: nonce + 1

  def prev_nonce(0), do: @mersenne_prime
  def prev_nonce(nonce), do: nonce - 1

  def new_candidate_nonce_count,
    do: Environment.get_env_or_default("NEW_CANDIDATE_NONCE_COUNT", 100)
end
