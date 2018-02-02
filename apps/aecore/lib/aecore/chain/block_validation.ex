defmodule Aecore.Chain.BlockValidation do

  alias Aecore.Pow.Cuckoo
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.ChainState
  alias Aecore.Chain.Difficulty

  @spec calculate_and_validate_block!(Block.t(), Block.t(), Chainstate.account_chainstate, list(Block.t())) :: {:error, term()} | :ok
  def calculate_and_validate_block!(new_block, previous_block, old_chain_state, blocks_for_difficulty_calculation) do

    is_genesis = new_block == Block.genesis_block() && previous_block == nil

    single_validate_block!(new_block)

    new_chain_state = ChainState.calculate_and_validate_chain_state!(new_block.txs, old_chain_state, new_block.header.height)

    chain_state_hash = ChainState.calculate_chain_state_hash(new_chain_state)

    is_difficulty_target_met = Cuckoo.verify(new_block.header)
    difficulty = Difficulty.calculate_next_difficulty(blocks_for_difficulty_calculation)

    cond do
      # do not check previous block hash for genesis block, there is none
      !(is_genesis || check_prev_hash?(new_block, previous_block)) ->
        throw({:error, "Incorrect previous hash"})

      # do not check previous block height for genesis block, there is none
      !(is_genesis || check_correct_height?(new_block, previous_block)) ->
        throw({:error, "Incorrect height"})

      !is_difficulty_target_met ->
        throw({:error, "Header hash doesnt meet the difficulty target"})

      new_block.header.chain_state_hash != chain_state_hash ->
        throw({:error, "Chain state hash not matching"})

      difficulty != new_block.header.difficulty_target ->
        throw({:error, "Invalid block difficulty"})

      true ->
        new_chain_state
    end
  end

  @spec single_validate_block!(Block.t()) :: {:error, term()} | :ok
  def single_validate_block!(block) do
    coinbase_transactions_sum = sum_coinbase_transactions(block)
    total_fees = Miner.calculate_total_fees(block.txs)
    cond do
      block.header.txs_hash != calculate_root_hash(block.txs) ->
        throw({:error, "Root hash of transactions does not match the one in header"})

      !(block |> validate_block_transactions() |> Enum.all?()) ->
        throw({:error, "One or more transactions not valid"})

      coinbase_transactions_sum > Miner.coinbase_transaction_value() + total_fees ->
        throw({:error, "Sum of coinbase transactions values exceeds the maximum coinbase transactions value"})

      block.header.version != Block.current_block_version() ->
        throw({:error, "Invalid block version"})

      true ->
        :ok
    end
  end

  @spec block_header_hash(Header.t) :: binary()
  def block_header_hash(%Header{} = header) do
    block_header_bin = :erlang.term_to_binary(header)
    :crypto.hash(:sha256, block_header_bin)
  end

  @spec validate_block_transactions(Block.t()) :: list(boolean())
  def validate_block_transactions(block) do
    block.txs
    |> Enum.map(fn tx ->
      SignedTx.is_coinbase?(tx) ||  SignedTx.is_valid?(tx)
    end)
  end

  @spec filter_invalid_transactions_chainstate(list(SignedTx.t()), map(), integer()) :: list(SignedTx.t())
  def filter_invalid_transactions_chainstate(txs_list, chain_state, block_height) do
    {valid_txs_list, _} = List.foldl(
      txs_list,
      {[], chain_state},
      fn (tx, {valid_txs_list, chain_state_acc}) ->
        {valid_chain_state, updated_chain_state} = validate_transaction_chainstate(tx, chain_state_acc, block_height)
        if valid_chain_state do
          {valid_txs_list ++ [tx], updated_chain_state}
        else
          {valid_txs_list, chain_state_acc}
        end
      end
    )

    valid_txs_list
  end

  @spec validate_transaction_chainstate(SignedTx.t(), ChainState.account_chainstate(), integer()) :: {boolean(), map()}
  defp validate_transaction_chainstate(tx, chain_state, block_height) do
    try do
      {true, ChainState.apply_transaction_on_state!(tx, chain_state, block_height)}
    catch
      {:error, _} -> {false, chain_state}
    end
  end

  @spec calculate_root_hash(list(SignedTx.t())) :: binary()
  def calculate_root_hash(txs) when txs == [] do
    <<0::256>>
  end

  @spec calculate_root_hash(list(SignedTx.t())) :: binary()
  def calculate_root_hash(txs)  do
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
        transaction_data_bin = :erlang.term_to_binary(transaction.data)
        {:crypto.hash(:sha256, transaction_data_bin), transaction_data_bin}
      end

      merkle_tree
      |> List.foldl(:gb_merkle_trees.empty(), fn node, merkle_tree ->
        :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree)
      end)
    end
  end

  @spec calculate_root_hash(Block.t()) :: integer()
  defp sum_coinbase_transactions(block) do
    block.txs
    |> Enum.map(fn tx ->
      if SignedTx.is_coinbase?(tx) do
        tx.data.value
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
end
