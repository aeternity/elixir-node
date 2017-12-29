defmodule Aecore.Chain.BlockValidation do

  alias Aecore.Pow.Cuckoo
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Structures.Block
  alias Aecore.Structures.Header
  alias Aecore.Structures.SignedTx
  alias Aecore.Chain.ChainState
  alias Aecore.Chain.Difficulty

  @spec validate_block!(Block.t, Block.t, map, list) :: {:error, term()} | :ok
  def validate_block!(new_block, previous_block, chain_state, blocks_for_difficulty_calculation) do

    is_genesis = new_block == Block.genesis_block() && previous_block == nil
    chain_state_hash = ChainState.calculate_chain_state_hash(chain_state)
    is_valid_chain_state = ChainState.validate_chain_state(chain_state)

    is_difficulty_target_met = Cuckoo.verify(new_block.header)
    difficulty = Difficulty.calculate_next_difficulty(blocks_for_difficulty_calculation)

    single_validate_block(new_block)

    cond do
      # do not check previous block hash for genesis block, there is none
      !(is_genesis || check_prev_hash(new_block, previous_block)) ->
        throw({:error, "Incorrect previous hash"})

      # do not check previous block height for genesis block, there is none
      !(is_genesis || check_correct_height(new_block, previous_block)) ->
        throw({:error, "Incorrect height"})

      !is_difficulty_target_met ->
        throw({:error, "Header hash doesnt meet the difficulty target"})

      new_block.header.chain_state_hash != chain_state_hash ->
        throw({:error, "Chain state hash not matching"})

      !is_valid_chain_state ->
        throw({:error, "Chain state not valid"})

      difficulty != new_block.header.difficulty_target ->
        throw({:error, "Invalid block difficulty"})

      true ->
        :ok
    end
  end

  @spec single_validate_block(Block.t) :: {:error, term()} | :ok
  def single_validate_block(block) do
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

  @spec block_header_hash(Header.t) :: binary
  def block_header_hash(%Header{} = header) do
    block_header_bin = :erlang.term_to_binary(header)
    :crypto.hash(:sha256, block_header_bin)
  end

  @spec validate_block_transactions(Block.t) :: list
  def validate_block_transactions(block) do
    block.txs |> Enum.map(fn tx -> SignedTx.is_coinbase(tx) ||  SignedTx.is_valid(tx) end)
  end

  @spec filter_invalid_transactions_chainstate(list, map) :: list
  def filter_invalid_transactions_chainstate(txs_list, chain_state) do
    {valid_txs_list, _} = List.foldl(
      txs_list,
      {[], chain_state},
      fn (tx, {valid_txs_list, chain_state_acc}) ->
        valid_tx = SignedTx.is_valid(tx)
        {valid_chain_state, updated_chain_state} = validate_transaction_chainstate(tx, chain_state_acc)

        if valid_tx && valid_chain_state do
            {valid_txs_list ++ [tx], updated_chain_state}
        else
            {valid_txs_list, chain_state_acc}
        end
      end
    )

    valid_txs_list
  end

  @spec validate_transaction_chainstate(SignedTx.t, map) :: {boolean(), map}
  defp validate_transaction_chainstate(tx, chain_state) do
    chain_state_has_account = Map.has_key?(chain_state, tx.data.from_acc)
    tx_has_valid_nonce = if chain_state_has_account do
      tx.data.nonce > Map.get(chain_state, tx.data.from_acc).nonce
    else
      true
    end

    from_account_has_necessary_balance =
      chain_state_has_account &&
        chain_state[tx.data.from_acc].balance - (tx.data.value + tx.data.fee) >= 0

    if tx_has_valid_nonce && from_account_has_necessary_balance do
      from_acc_new_state = %{balance: -(tx.data.value + tx.data.fee), nonce: 1, locked: []}
      to_acc_new_state = %{balance: tx.data.value, nonce: 0, locked: []}
      chain_state_changes = %{tx.data.from_acc => from_acc_new_state, tx.data.to_acc => to_acc_new_state}
      updated_chain_state = ChainState.calculate_chain_state(chain_state_changes, chain_state)
      {true, updated_chain_state}
    else
      {false, chain_state}
    end
  end

  @spec calculate_root_hash(list) :: binary
  def calculate_root_hash(txs) do
    if Enum.empty?(txs) do
      <<0::256>>
    else
      merkle_tree =
        for transaction <- txs do
          transaction_data_bin = :erlang.term_to_binary(transaction.data)
          {:crypto.hash(:sha256, transaction_data_bin), transaction_data_bin}
        end

      merkle_tree =
        merkle_tree
        |> List.foldl(:gb_merkle_trees.empty(), fn node, merkle_tree ->
             :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree)
           end)

      merkle_tree |> :gb_merkle_trees.root_hash()
    end
  end

  @spec calculate_root_hash(Block.t) :: integer
  defp sum_coinbase_transactions(block) do
    block.txs
    |> Enum.map(fn tx ->
      if SignedTx.is_coinbase(tx) do
        tx.data.value
      else
        0
      end
    end)
    |> Enum.sum()
  end

  @spec check_prev_hash(Block.t, Block.t) :: boolean()
  defp check_prev_hash(new_block, previous_block) do
    prev_block_header_hash = block_header_hash(previous_block.header)
    new_block.header.prev_hash == prev_block_header_hash
  end

  @spec check_correct_height(Block.t, Block.t) :: boolean()
  defp check_correct_height(new_block, previous_block) do
    previous_block.header.height + 1 == new_block.header.height
  end

end
