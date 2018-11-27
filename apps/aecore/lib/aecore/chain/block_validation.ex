defmodule Aecore.Chain.BlockValidation do
  @moduledoc """
  Contains functions used to validate data inside of the block structure
  """

  alias Aecore.Chain.{KeyBlock, MicroBlock, Chainstate, Genesis, KeyHeader, MicroHeader}
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Tx.{SignedTx}
  alias Aecore.Util.Header
  alias Aeutil.PatriciaMerkleTree
  alias Aeutil.Serialization
  alias MerklePatriciaTree.Trie

  @spec calculate_and_validate_block(
          KeyBlock.t() | MicroBlock.t(),
          KeyBlock.t() | MicroBlock.t(),
          Chainstate.t(),
          list(KeyBlock.t())
        ) :: {:ok, Chainstate.t()} | {:error, String.t()}

  def calculate_and_validate_block(
        %{header: %{height: height, version: version, root_hash: root_hash}} = new_block,
        previous_block,
        old_chain_state,
        blocks_for_target_calculation
      ) do
    block_specifically_valid =
      case new_block do
        %KeyBlock{} ->
          KeyBlock.validate(new_block, blocks_for_target_calculation)

        %MicroBlock{} ->
          MicroBlock.validate(new_block, previous_block)
      end

    is_genesis = new_block == Genesis.block() && previous_block == nil

    with :ok <- block_specifically_valid,
         {:ok, new_chain_state} <-
           Chainstate.calculate_and_validate_chain_state(new_block, old_chain_state, height) do
      expected_root_hash = Chainstate.calculate_root_hash(new_chain_state)

      cond do
        # do not check previous block height for genesis block, there is none
        !(is_genesis || check_correct_height?(new_block, previous_block)) ->
          {:error, "#{__MODULE__}: Incorrect height"}

        !valid_prev_hash?(new_block, previous_block) ->
          {:error, "#{__MODULE__}: Incorrect previous block hash"}

        !valid_prev_key_hash?(new_block, previous_block) ->
          {:error, "#{__MODULE__}: Incorrect previous key block hash"}

        version != GovernanceConstants.protocol_version() ->
          {:error, "#{__MODULE__}: Invalid protocol version"}

        !valid_header_time?(new_block) ->
          {:error, "#{__MODULE__}: Invalid header time"}

        root_hash != expected_root_hash ->
          {:error, "#{__MODULE__}: Root hash not matching"}

        true ->
          {:ok, new_chain_state}
      end
    else
      {:error, _} = error ->
        error
    end
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

  defp valid_prev_hash?(%{header: %{prev_hash: new_prev_hash}}, %{
         header: %{} = prev_header
       }) do
    new_prev_hash == Header.hash(prev_header)
  end

  defp valid_prev_key_hash?(%{header: %{prev_key_hash: new_prev_key_hash}}, %{
         header: %{} = prev_header
       }) do
    new_prev_key_hash == Header.top_key_block_hash(prev_header)
  end

  @spec check_correct_height?(KeyBlock.t() | MicroBlock.t(), KeyBlock.t() | MicroBlock.t()) ::
          boolean()
  defp check_correct_height?(%KeyBlock{header: %KeyHeader{height: new_block_height}}, %{
         header: %{height: previous_block_height}
       }) do
    previous_block_height + 1 == new_block_height
  end

  defp check_correct_height?(%MicroBlock{header: %MicroHeader{height: new_block_height}}, %{
         header: %{height: previous_block_height}
       }) do
    previous_block_height == new_block_height
  end

  @spec valid_header_time?(KeyBlock.t() | MicroBlock.t()) :: boolean()
  defp valid_header_time?(%{header: %{time: time}}) do
    time <
      System.system_time(:milliseconds) + GovernanceConstants.time_validation_future_limit_ms()
  end
end
