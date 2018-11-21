defmodule Aecore.Chain.BlockValidation do
  @moduledoc """
  Contains functions used to validate data inside of the block structure
  """

  alias Aecore.Chain.{KeyBlock, MicroBlock, Chainstate, Genesis, KeyHeader, MicroHeader, Target}
  alias Aecore.Chain.Worker, as: Chain
  alias Aecore.Keys
  alias Aecore.Governance.GovernanceConstants
  alias Aecore.Pow.Pow
  alias Aecore.Tx.{DataTx, SignedTx}
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
          validate_key_block(new_block, blocks_for_target_calculation)

        %MicroBlock{} ->
          validate_micro_block(new_block, previous_block)
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

  defp validate_key_block(
         %KeyBlock{
           header: %KeyHeader{target: target, time: time} = header
         },
         blocks_for_target_calculation
       ) do
    expected_target =
      Target.calculate_next_target(
        time,
        blocks_for_target_calculation
      )

    cond do
      target != expected_target ->
        {:error, "#{__MODULE__}: Invalid block target"}

      !is_solution_valid?(header) ->
        {:error, "#{__MODULE__}: Invalid PoW solution"}

      true ->
        :ok
    end
  end

  defp validate_micro_block(
         %MicroBlock{
           header:
             %MicroHeader{time: new_time, signature: signature, txs_hash: txs_hash} = header,
           txs: txs
         },
         %{
           header: %{time: prev_block_time, prev_key_hash: prev_key_hash} = prev_header
         } = prev_block
       ) do
    prev_key_block =
      case prev_block do
        %KeyBlock{} ->
          prev_block

        %MicroBlock{} ->
          {:ok, key_block} = Chain.get_block(prev_key_hash)
          key_block
      end

    # header was signed with this signature in mining
    header_with_zero_signature = %{header | signature: <<0::512>>}

    is_signature_valid =
      header_with_zero_signature
      |> MicroHeader.encode_to_binary()
      |> Keys.verify(signature, prev_key_block.header.miner)

    is_minimum_distance_met =
      case prev_header do
        %KeyHeader{} ->
          new_time > prev_block_time

        %MicroHeader{} ->
          new_time >= prev_block_time + GovernanceConstants.micro_block_distance()
      end

    cond do
      !is_minimum_distance_met ->
        {:error, "#{__MODULE__}: Micro block too close to previous block"}

      !is_signature_valid ->
        {:error, "#{__MODULE__}: Invalid micro block signature"}

      txs_hash != calculate_txs_hash(txs) ->
        {:error, "#{__MODULE__}: Root hash of transactions does not match the one in header"}

      true ->
        :ok
    end
  end

  @spec validate_block_transactions(MicroBlock.t()) :: list(boolean())
  def validate_block_transactions(%MicroBlock{txs: txs}) do
    Enum.map(txs, fn tx -> :ok == SignedTx.validate(tx) end)
  end

  @spec txs_meet_minimum_fee?(list(SignedTx.t()), Chainstate.t(), non_neg_integer()) :: boolean()
  def txs_meet_minimum_fee?(txs, chain_state, block_height) do
    Enum.all?(txs, fn %SignedTx{data: %DataTx{type: type} = data_tx} ->
      type.is_minimum_fee_met?(
        data_tx,
        Map.get(chain_state, type.get_chain_state_name()),
        block_height
      )
    end)
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

  @spec is_solution_valid?(KeyHeader.t()) :: boolean()
  defp is_solution_valid?(%KeyHeader{} = header) do
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
