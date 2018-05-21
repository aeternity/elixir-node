defmodule Aecore.Chain.BlockValidation do
  @moduledoc """
  Contains functions used to validate data inside of the block structure
  """

  alias Aecore.Pow.Cuckoo
  alias Aecore.Miner.Worker, as: Miner
  alias Aecore.Chain.Block
  alias Aecore.Chain.Header
  alias Aecore.Tx.SignedTx
  alias Aecore.Account.Tx.SpendTx
  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Difficulty
  alias Aeutil.Serialization
  alias Aeutil.Hash

  @time_validation_future_limit_ms 30 * 60 * 1000

  @type tree :: :gb_merkle_trees.tree()

  @spec calculate_and_validate_block(
          Block.t(),
          Block.t(),
          Chainstate.chainstate(),
          list(Block.t())
        ) :: {:ok, Chainstate.t()} | {:error, String.t()}
  def calculate_and_validate_block(
        new_block,
        previous_block,
        old_chain_state,
        blocks_for_target_calculation
      ) do
    is_genesis = new_block == Block.genesis_block() && previous_block == nil

    case single_validate_block(new_block) do
      :ok ->
        {:ok, new_chain_state} =
          Chainstate.calculate_and_validate_chain_state(
            new_block.txs,
            old_chain_state,
            new_block.header.height
          )

        root_hash = Chainstate.calculate_root_hash(new_chain_state)

        target =
          Difficulty.calculate_next_difficulty(
            new_block.header.time,
            blocks_for_target_calculation
          )

        cond do
          # do not check previous block height for genesis block, there is none
          !(is_genesis || check_correct_height?(new_block, previous_block)) ->
            {:error, "#{__MODULE__}: Incorrect height"}

          !valid_header_time?(new_block) ->
            {:error, "#{__MODULE__}: Invalid header time"}

          new_block.header.root_hash != root_hash ->
            {:error, "#{__MODULE__}: Root hash not matching"}

          target != new_block.header.target ->
            {:error, "#{__MODULE__}: Invalid block target"}

          true ->
            {:ok, new_chain_state}
        end

      err ->
        err
    end
  end

  @spec single_validate_block(Block.t()) :: :ok | {:error, String.t()}
  def single_validate_block(block) do
    coinbase_transactions_sum = sum_coinbase_transactions(block)
    total_fees = Miner.calculate_total_fees(block.txs)
    server = self()
    work = fn -> Cuckoo.verify(block.header) end

    spawn(fn ->
      send(server, {:worker_reply, self(), work.()})
    end)

    is_target_met =
      receive do
        {:worker_reply, _from, verified?} -> verified?
      end

    block_txs_count = length(block.txs)
    max_txs_for_block = Application.get_env(:aecore, :tx_data)[:max_txs_per_block]

    cond do
      block.header.txs_hash != calculate_txs_hash(block.txs) ->
        {:error, "#{__MODULE__}: Root hash of transactions does not match the one in header"}

      !(block |> validate_block_transactions() |> Enum.all?()) ->
        {:error, "#{__MODULE__}: One or more transactions not valid"}

      coinbase_transactions_sum > Miner.coinbase_transaction_amount() + total_fees ->
        {:error, "#{__MODULE__}: Sum of coinbase transactions amounts exceeds
             the maximum coinbase transactions amount"}

      block.header.version != Block.current_block_version() ->
        {:error, "#{__MODULE__}: Invalid block version"}

      block_txs_count > max_txs_for_block ->
        {:error, "#{__MODULE__}: Too many transactions"}

      !valid_header_time?(block) ->
        {:error, "#{__MODULE__}: Invalid header time"}

      !is_target_met ->
        {:error, "#{__MODULE__}: Header hash doesnt meet the target"}

      true ->
        :ok
    end
  end

  @spec block_header_hash(Header.t()) :: binary()
  def block_header_hash(%Header{} = header) do
    block_header_bin = Serialization.pack_binary(header)
    Hash.hash(block_header_bin)
  end

  @spec validate_block_transactions(Block.t()) :: list(boolean())
  def validate_block_transactions(block) do
    block.txs
    |> Enum.map(fn tx ->
      SignedTx.is_coinbase?(tx) || :ok == SignedTx.validate(tx)
    end)
  end

  @spec calculate_txs_hash([]) :: binary()
  def calculate_txs_hash(txs) when txs == [] do
    <<0::256>>
  end

  @spec calculate_txs_hash(nonempty_list(SignedTx.t())) :: binary()
  def calculate_txs_hash(txs) do
    txs
    |> build_merkle_tree()
    |> :gb_merkle_trees.root_hash()
  end

  @spec build_merkle_tree(list(SignedTx.t())) :: tree()
  def build_merkle_tree(txs) do
    if Enum.empty?(txs) do
      <<0::256>>
    else
      merkle_tree =
        for transaction <- txs do
          transaction_data_bin = Serialization.pack_binary(transaction.data)
          {Hash.hash(transaction_data_bin), transaction_data_bin}
        end

      merkle_tree
      |> List.foldl(:gb_merkle_trees.empty(), fn node, merkle_tree ->
        :gb_merkle_trees.enter(elem(node, 0), elem(node, 1), merkle_tree)
      end)
    end
  end

  @spec sum_coinbase_transactions(Block.t()) :: non_neg_integer()
  defp sum_coinbase_transactions(block) do
    txs_list_only_spend_txs =
      Enum.filter(block.txs, fn tx ->
        match?(%SpendTx{}, tx.data)
      end)

    txs_list_only_spend_txs
    |> Enum.map(fn tx ->
      if SignedTx.is_coinbase?(tx) do
        tx.data.payload.amount
      else
        0
      end
    end)
    |> Enum.sum()
  end

  @spec check_correct_height?(Block.t(), Block.t()) :: boolean()
  defp check_correct_height?(new_block, previous_block) do
    previous_block.header.height + 1 == new_block.header.height
  end

  @spec valid_header_time?(Block.t()) :: boolean()
  defp valid_header_time?(%Block{header: new_block_header}) do
    new_block_header.time < System.system_time(:milliseconds) + @time_validation_future_limit_ms
  end
end
