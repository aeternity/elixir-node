defmodule Aecore.Chain.BlockValidation do
  @moduledoc """
  Contains functions used to validate data inside of the block structure
  """

  alias Aecore.Pow.Cuckoo
  alias Aecore.Chain.{Block, Header, Genesis}
  alias Aecore.Tx.SignedTx
  alias Aecore.Chain.Chainstate
  alias Aecore.Chain.Target
  alias Aeutil.Hash
  alias Aecore.Chain.Chainstate
  alias Aecore.Governance.GovernanceConstants
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
        new_block,
        previous_block,
        old_chain_state,
        blocks_for_target_calculation
      ) do
    is_genesis = new_block == Genesis.block() && previous_block == nil

    case single_validate_block(new_block) do
      :ok ->
        {:ok, new_chain_state} =
          Chainstate.calculate_and_validate_chain_state(
            new_block.txs,
            old_chain_state,
            new_block.header.height,
            new_block.header.miner
          )

        root_hash = Chainstate.calculate_root_hash(new_chain_state)

        target =
          Target.calculate_next_target(
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
    block_header_bin = Header.encode_to_binary(header)
    Hash.hash(block_header_bin)
  end

  @spec validate_block_transactions(Block.t()) :: list(boolean())
  def validate_block_transactions(block) do
    block.txs |> Enum.map(fn tx -> :ok == SignedTx.validate(tx) end)
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
  defp check_correct_height?(new_block, previous_block) do
    previous_block.header.height + 1 == new_block.header.height
  end

  @spec valid_header_time?(Block.t()) :: boolean()
  defp valid_header_time?(%Block{header: new_block_header}) do
    new_block_header.time <
      System.system_time(:milliseconds) + GovernanceConstants.time_validation_future_limit_ms()
  end
end
