defmodule Aecore.Chain.BlockValidation do
  @moduledoc """
  Contains functions used to validate data inside of the block structure
  """

  require Logger

  alias Aecore.Pow.Cuckoo
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.ChainState
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Chain.Difficulty
  alias Aeutil.Serialization

  @time_validation_blocks_count 10
  @time_validation_future_limit_ms 3_600_000

  @spec calculate_and_validate_block!(
          Block.t(),
          Block.t(),
          ChainState.account_chainstate(),
          list(Block.t())
        ) :: {:error, term()} | :ok

  def calculate_and_validate_block!(
        new_block,
        previous_block,
        old_chain_state,
        blocks_for_target_calculation
      ) do
    is_genesis = new_block == Block.genesis_block() && previous_block == nil

    single_validate_block!(new_block)

    new_chain_state =
      ChainState.calculate_and_validate_chain_state!(
        new_block.txs,
        old_chain_state
      )

    root_hash = ChainState.calculate_root_hash(new_chain_state)

    server = self()
    work = fn -> Cuckoo.verify(new_block.header) end

    spawn(fn ->
      send(server, {:worker_reply, self(), work.()})
    end)

    is_target_met =
      receive do
        {:worker_reply, _from, verified?} -> verified?
      end

    target = Difficulty.calculate_next_target(blocks_for_target_calculation)

    cond do
      # do not check previous block hash for genesis block, there is none
      !(is_genesis || check_prev_hash?(new_block, previous_block)) ->
        throw({:error, "Incorrect previous hash"})

      # do not check previous block height for genesis block, there is none
      !(is_genesis || check_correct_height?(new_block, previous_block)) ->
        throw({:error, "Incorrect height"})

      !valid_header_time?(new_block) ->
        throw({:error, "Invalid header time"})

      !is_target_met ->
        throw({:error, "Header hash doesnt meet the target"})

      new_block.header.root_hash != root_hash ->
        throw({:error, "Root hash not matching"})

      target != new_block.header.target ->
        throw({:error, "Invalid block target"})

      true ->
        new_chain_state
    end
  end

  @spec single_validate_block!(Block.t()) :: {:error, term()} | :ok
  def single_validate_block!(block) do
    coinbase_transactions_sum = sum_coinbase_transactions(block)
    total_fees = Miner.calculate_total_fees(block.txs)
    block_size_bytes = block |> :erlang.term_to_binary() |> :erlang.byte_size()

    cond do
      block.header.txs_hash != calculate_txs_hash(block.txs) ->
        throw({:error, "Root hash of transactions does not match the one in header"})

      !(block |> validate_block_transactions() |> Enum.all?()) ->
        throw({:error, "One or more transactions not valid"})

      coinbase_transactions_sum > Miner.coinbase_transaction_amount() + total_fees ->
        throw(
          {:error,
           "Sum of coinbase transactions amounts exceeds the maximum coinbase transactions amount"}
        )

      block.header.version != Block.current_block_version() ->
        throw({:error, "Invalid block version"})

      block_size_bytes > Application.get_env(:aecore, :block)[:max_block_size_bytes] ->
        throw({:error, "Block size is too big"})

      true ->
        :ok
    end
  end

  @spec block_header_hash(Header.t()) :: binary()
  def block_header_hash(%Header{} = header) do
    block_header_bin = Serialization.pack_binary(header)
    :crypto.hash(:sha256, block_header_bin)
  end

  @spec validate_block_transactions(Block.t()) :: list(boolean())
  def validate_block_transactions(block) do
    block.txs
    |> Enum.map(fn tx ->
      SignedTx.is_coinbase?(tx) || SignedTx.is_valid?(tx)
    end)
  end

  @spec calculate_txs_hash(list(SignedTx.t())) :: binary()
  def calculate_txs_hash(txs) when txs == [] do
    <<0::256>>
  end

  @spec calculate_txs_hash(list(SignedTx.t())) :: binary()
  def calculate_txs_hash(txs) do
    txs
    |> build_merkle_tree()
    |> :gb_merkle_trees.root_hash()
  end

  @spec build_merkle_tree(list(SignedTx.t())) :: tuple()
  def build_merkle_tree(txs) do
    if Enum.empty?(txs) do
      <<0::256>>
    else
      merkle_tree =
        for transaction <- txs do
          transaction_data_bin = Serialization.pack_binary(transaction.data)
          {:crypto.hash(:sha256, transaction_data_bin), transaction_data_bin}
        end

      merkle_tree
      |> List.foldl(:gb_merkle_trees.empty(), fn node, merkle_tree ->
        :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree)
      end)
    end
  end

  @spec sum_coinbase_transactions(Block.t()) :: integer()
  defp sum_coinbase_transactions(block) do
    block.txs
    |> Enum.map(fn tx ->
      if SignedTx.is_coinbase?(tx) do
        tx.data.payload.amount
      else
        0
      end
    end)
    |> Enum.sum()
  end

  @spec check_prev_hash?(Block.t(), Block.t()) :: boolean()
  defp check_prev_hash?(new_block, previous_block) do
    prev_block_header_hash = block_header_hash(previous_block.header)
    new_block.header.prev_hash == prev_block_header_hash
  end

  @spec check_correct_height?(Block.t(), Block.t()) :: boolean()
  defp check_correct_height?(new_block, previous_block) do
    previous_block.header.height + 1 == new_block.header.height
  end

  @spec valid_header_time?(Block.t()) :: boolean()
  defp valid_header_time?(%Block{header: new_block_header}) do
    case new_block_header.time <=
           System.system_time(:milliseconds) + @time_validation_future_limit_ms do
      true ->
        last_blocks = Chain.get_blocks(Chain.top_block_hash(), @time_validation_blocks_count)

        last_blocks_times = for block <- last_blocks, do: block.header.time

        avg = Enum.sum(last_blocks_times) / Enum.count(last_blocks_times)

        new_block_header.time >= avg

      false ->
        false
    end
  end
end
