defmodule Aecore.Chain.BlockValidation do
  @moduledoc """
  Contains functions used to validate data inside of the block structure
  """

  alias Aecore.Chain.{Block, Chainstate, Genesis, Header, Target}
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Pow.Pow
  alias Aecore.Tx.SignedTx
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias MerklePatriciaTree.Trie

  @spec calculate_and_validate_block(
          Block.t(),
          Block.t(),
          Chainstate.t(),
          list(Block.t())
        ) :: {:ok, Chainstate.t()} | {:error, String.t()}
  def calculate_and_validate_block(
        %Block{
          header: %Header{
            height: height,
            miner: miner,
            time: time,
            root_hash: root_hash,
            target: target
          },
          txs: txs
        } = new_block,
        previous_block,
        old_chain_state,
        blocks_for_target_calculation
      ) do
    is_genesis = new_block == Genesis.block() && previous_block == nil

    case single_validate_block(new_block) do
      :ok ->
        {:ok, new_chain_state} =
          Chainstate.calculate_and_validate_chain_state(
            txs,
            old_chain_state,
            height,
            miner
          )

        expected_root_hash = Chainstate.calculate_root_hash(new_chain_state)

        expected_target =
          Target.calculate_next_target(
            time,
            blocks_for_target_calculation
          )

        cond do
          # do not check previous block height for genesis block, there is none
          !(is_genesis || check_correct_height?(new_block, previous_block)) ->
            {:error, "#{__MODULE__}: Incorrect height"}

          !valid_header_time?(new_block) ->
            {:error, "#{__MODULE__}: Invalid header time"}

          root_hash != expected_root_hash ->
            {:error, "#{__MODULE__}: Root hash not matching"}

          target != expected_target ->
            {:error, "#{__MODULE__}: Invalid block target"}

          true ->
            {:ok, new_chain_state}
        end

      {:error, _} = error ->
        error
    end
  end

  @spec single_validate_block(Block.t()) :: :ok | {:error, String.t()}
  def single_validate_block(
        %Block{
          header: %Header{txs_hash: txs_hash, version: version} = header,
          txs: txs
        } = block
      ) do
    block_txs_count = length(txs)

    cond do
      txs_hash != calculate_txs_hash(txs) ->
        {:error, "#{__MODULE__}: Root hash of transactions does not match the one in header"}

      !(block |> validate_block_transactions() |> Enum.all?()) ->
        {:error, "#{__MODULE__}: One or more transactions not valid"}

      version != Block.current_block_version() ->
        {:error, "#{__MODULE__}: Invalid block version"}

      block_txs_count > GovernanceConstants.max_txs_per_block() ->
        {:error, "#{__MODULE__}: Too many transactions"}

      !valid_header_time?(block) ->
        {:error, "#{__MODULE__}: Invalid header time"}

      !is_target_met?(header) ->
        {:error, "#{__MODULE__}: Header hash doesnt meet the target"}

      true ->
        :ok
    end
  end

  @spec validate_block_transactions(Block.t()) :: list(boolean())
  def validate_block_transactions(%Block{txs: txs}) do
    Enum.map(txs, fn tx -> :ok == SignedTx.validate(tx) end)
  end

  @spec calculate_txs_hash([]) :: binary()
  def calculate_txs_hash([]), do: <<0::256>>

  @spec calculate_txs_hash(nonempty_list(SignedTx.t())) :: binary()
  def calculate_txs_hash(txs) do
    txs
    |> build_merkle_tree()
    |> PatriciaMerkleTree.root_hash()
  end

  @spec build_merkle_tree(list(SignedTx.t())) :: Trie.t()
  def build_merkle_tree(txs) do
    build_merkle_tree(txs, 0, PatriciaMerkleTree.new(:txs))
  end

  defp build_merkle_tree([], _position, tree), do: tree

  defp build_merkle_tree([%SignedTx{} = signed_tx | list_txs], position, tree) do
    key = :binary.encode_unsigned(position)
    val = Serialization.rlp_encode(signed_tx)
    build_merkle_tree(list_txs, position + 1, PatriciaMerkleTree.enter(tree, key, val))
  end

  @spec check_correct_height?(Block.t(), Block.t()) :: boolean()
  defp check_correct_height?(%Block{header: %Header{height: new_block_height}}, %Block{
         header: %Header{height: previous_block_height}
       }) do
    previous_block_height + 1 == new_block_height
  end

  @spec valid_header_time?(Block.t()) :: boolean()
  defp valid_header_time?(%Block{header: %Header{time: time}}) do
    time <
      System.system_time(:milliseconds) + GovernanceConstants.time_validation_future_limit_ms()
  end

  @spec is_target_met?(Header.t()) :: true | false
  defp is_target_met?(%Header{} = header) do
    server_pid = self()
    work = fn -> Pow.verify(header) end

    Task.start(fn ->
      send(server_pid, {:worker_reply, self(), work.()})
    end)

    receive do
      {:worker_reply, _from, verified?} -> verified?
    end
  end
end
